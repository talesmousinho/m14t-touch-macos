import ApplicationServices
import CoreGraphics
import Foundation
import IOKit.hid

/// Orchestrates the M14t USB HID digitizer, live display tracking, multi-touch
/// `GestureEngine`, and `MouseEmitter`.
public final class HIDTouchDriver {

    public private(set) var config: TouchConfig
    private let emitter = MouseEmitter()
    private let gestureEngine: GestureEngine

    // IOKit HID state
    private var manager: IOHIDManager?

    private struct FingerSlotKey: Hashable {
        let device: UnsafeMutableRawPointer
        let reportID: UInt32
        let collectionCookie: IOHIDElementCookie
    }

    private struct FingerSlotState {
        var slotID: Int
        var tipSwitch: Bool = false
        var rawX: Double = 0
        var rawY: Double = 0
        var hasX: Bool = false
        var hasY: Bool = false
        var maxX: Double = HID.Hardware.touchMaxX
        var maxY: Double = HID.Hardware.touchMaxY
    }

    private struct StylusState {
        var tipSwitch: Bool = false
        var barrelSwitch: Bool = false
        var secondaryBarrelSwitch: Bool = false
        var eraser: Bool = false
        var invert: Bool = false
        var inRange: Bool = false
        var rawX: Double = 0
        var rawY: Double = 0
        var maxX: Double = HID.Hardware.penMaxX
        var maxY: Double = HID.Hardware.penMaxY
        var rawPressure: Double = 0
        var maxPressure: Double = HID.Hardware.penMaxPressure
        var tiltX: Double = 0
        var tiltY: Double = 0
        var dirty: Bool = false
    }

    private var fingerSlots: [FingerSlotKey: FingerSlotState] = [:]
    private var stylusState = StylusState()
    private var hasSeenPrimaryReport0x0C = false
    private var frameFlushScheduled = false
    private var previousActiveFingerCount = 0
    private var isTouchActive = false
    private var hasAppliedResolutionPreset = false

    // Display & Coordinate mapping state
    private var calibration: CalibrationData = .m14tFactory
    private var mapper: CoordinateMapper
    private var displayObserver: DisplayReconfigurationObserver?
    private var currentDisplay: DisplayInfo?
    private var observed = ObservedRange()

    // Cursor Auto-Return to Main Display state
    private var cursorMovedByTouchToExternal = false
    private var lastMainDisplayPosition: CGPoint?
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?

    // Timers for stationary long-press right-click and Accessibility permission polling
    private var holdTimer: DispatchSourceTimer?
    private var permissionTimer: DispatchSourceTimer?
    private var isAccessibilityTrusted = false

    public init(config: TouchConfig) {
        self.config = config
        self.gestureEngine = GestureEngine(config: config)
        self.mapper = CoordinateMapper(
            calibration: .m14tFactory,
            displayBounds: .zero,
            invertX: config.invertX,
            invertY: config.invertY,
            rotationDegrees: 0
        )
        refreshTargetDisplay(logUpdate: false)
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    public func start() {
        refreshTargetDisplay(logUpdate: true)

        let observer = DisplayReconfigurationObserver { [weak self] in
            self?.refreshTargetDisplay(logUpdate: true)
        }
        observer.start()
        self.displayObserver = observer

        openHIDManager()
        startPermissionMonitor()
        startHoldWatchdog()
        setupCursorAutoReturnTap()
    }

    private func openHIDManager() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey: HID.Page.digitizer.rawValue,
            kIOHIDDeviceUsageKey: HID.Digitizer.touchScreen.rawValue
        ] as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
            HIDTouchDriver.from(ctx).deviceConnected(device)
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, device in
            HIDTouchDriver.from(ctx).deviceRemoved(device)
        }, context)

        IOHIDManagerRegisterInputValueCallback(manager, { ctx, _, _, value in
            HIDTouchDriver.from(ctx).handleInputValue(value)
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnSuccess {
            log("✅ Listening for M14t multi-touch & Smart Pencil events…")
        } else {
            log("⚠️  IOHIDManagerOpen returned \(String(format: "0x%08X", UInt32(bitPattern: result)))")
        }
        updateDaemonState()
    }

    public func stop() {
        tearDownCursorAutoReturnTap()
        holdTimer?.cancel()
        holdTimer = nil
        permissionTimer?.cancel()
        permissionTimer = nil
        displayObserver?.stop()
        displayObserver = nil

        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            self.manager = nil
        }
        fingerSlots.removeAll()
    }

    private static func from(_ ctx: UnsafeMutableRawPointer?) -> HIDTouchDriver {
        Unmanaged<HIDTouchDriver>.fromOpaque(ctx!).takeUnretainedValue()
    }

    // MARK: - Accessibility Permission Monitor

    private func updateDaemonState() {
        let trusted = AXIsProcessTrusted()
        let binaryPath = CommandLine.arguments.first ?? "m14ttouch"
        let state = DaemonState(
            pid: Int(ProcessInfo.processInfo.processIdentifier),
            isAccessibilityTrusted: trusted,
            isInputMonitoringTrusted: true,
            binaryPath: binaryPath
        )
        DaemonStateStore.save(state)
    }

    private func startPermissionMonitor() {
        isAccessibilityTrusted = AXIsProcessTrusted()
        updateDaemonState()

        if isAccessibilityTrusted {
            log("✅ Accessibility permission active")
            setupCursorAutoReturnTap()
        } else {
            log("⏳ Waiting for Accessibility permission in System Settings → Privacy & Security → Accessibility…")
            if config.promptForAccessibility {
                let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            }
        }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .seconds(2), repeating: .seconds(2))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let trustedNow = AXIsProcessTrusted()
            self.updateDaemonState()

            if trustedNow && !self.isAccessibilityTrusted {
                self.isAccessibilityTrusted = true
                self.log("✅ Accessibility permission granted — pointer & trackpad gestures active!")
                self.setupCursorAutoReturnTap()
            } else if !trustedNow && self.isAccessibilityTrusted {
                self.isAccessibilityTrusted = false
                self.tearDownCursorAutoReturnTap()
            }
        }
        self.permissionTimer = timer
        timer.resume()
    }

    // MARK: - Display Resolution & Hotplug

    public func refreshTargetDisplay(logUpdate: Bool) {
        guard var resolved = DisplayResolver.resolve(
            forIndex: config.displayIndex,
            preferAutoDetectM14t: config.autoDetectM14tDisplay
        ) else {
            return
        }

        if !hasAppliedResolutionPreset, config.displayResolutionPreset != .systemDefault {
            hasAppliedResolutionPreset = true
            switch DisplayResolver.applyResolutionPreset(config.displayResolutionPreset, to: resolved.id) {
            case .success(let msg):
                if logUpdate { log("📐 \(msg)") }
                if let updated = DisplayResolver.resolve(
                    forIndex: config.displayIndex,
                    preferAutoDetectM14t: config.autoDetectM14tDisplay
                ) {
                    resolved = updated
                }
            case .failure(let err):
                if logUpdate { log("⚠️  Display resolution switch failed: \(err.localizedDescription)") }
            }
        }

        let changed = (currentDisplay != resolved)
        currentDisplay = resolved
        mapper.displayBounds = resolved.bounds
        mapper.rotationDegrees = resolved.rotationDegrees

        if logUpdate && changed {
            let tag = resolved.isM14t ? "M14t auto-detected" : (resolved.isMain ? "main fallback" : "external")
            let dpiTag = resolved.isHiDPI
                ? "2x HiDPI (\(resolved.pixelWidth)×\(resolved.pixelHeight) px)"
                : "1x (\(resolved.pixelWidth)×\(resolved.pixelHeight) px)"
            log(
                "🖥️  Target display [\(resolved.index)] \"\(resolved.name)\" (\(tag)): " +
                "\(Int(resolved.bounds.width))×\(Int(resolved.bounds.height)) [\(dpiTag)] " +
                "@ (\(Int(resolved.bounds.minX)),\(Int(resolved.bounds.minY))) " +
                "rot=\(resolved.rotationDegrees)°"
            )
        }
    }

    // MARK: - Device Callbacks

    private func deviceConnected(_ device: IOHIDDevice) {
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
        let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let maxInput = IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 0

        log("🔌 Connected: \"\(name)\"  VID 0x\(hex(vendor))  PID 0x\(hex(product))  maxReport=\(maxInput)B")

        refreshTargetDisplay(logUpdate: true)
        resolveCalibration()
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        log("🔌 Touch device disconnected")
        let devPtr = Unmanaged.passUnretained(device).toOpaque()
        fingerSlots = fingerSlots.filter { $0.key.device != devPtr }
        let releaseActions = gestureEngine.reset()
        emitter.execute(releaseActions)
        isTouchActive = false
    }

    // MARK: - Calibration Resolution

    private func resolveCalibration() {
        var resolved = CalibrationData.m14tFactory

        if let saved = CalibrationStore.load(), !config.hasManualCalibration, !config.autoCalibrate {
            resolved = saved
            observed.seed(with: saved)
            log("💾 Loaded custom calibration: \(describe(resolved))")
        }

        if let v = config.manualXMin { resolved.xMin = v }
        if let v = config.manualXMax { resolved.xMax = v }
        if let v = config.manualYMin { resolved.yMin = v }
        if let v = config.manualYMax { resolved.yMax = v }

        calibration = resolved
        mapper.calibration = resolved

        if config.autoCalibrate {
            log("🎯 Auto-calibrate ON — touch all four corners of the M14t screen")
        }
    }

    // MARK: - Frame-Coalesced Input Value Handling

    private func handleInputValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let reportID = IOHIDElementGetReportID(element)

        // Ignore legacy Mouse Emulation collection (ReportID 1, 0..32767)
        if reportID == UInt32(HID.ReportID.mouseFallback) {
            return
        }

        if reportID == UInt32(HID.ReportID.multiTouch) {
            hasSeenPrimaryReport0x0C = true
        } else if reportID == UInt32(HID.ReportID.secondaryTouch) && hasSeenPrimaryReport0x0C {
            return
        }

        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intVal = IOHIDValueGetIntegerValue(value)
        let logicalMax = Double(IOHIDElementGetLogicalMax(element))

        if config.debugMode {
            log("HID  report=\(reportID) page=0x\(hex(Int(page))) usage=0x\(hex(Int(usage))) val=\(intVal) max=\(Int(logicalMax))")
        }

        let parent = IOHIDElementGetParent(element)
        let parentUsage = parent.map { IOHIDElementGetUsage($0) } ?? 0
        if reportID == UInt32(HID.ReportID.stylus) || reportID == UInt32(HID.ReportID.stylusVendor) || parentUsage == HID.Digitizer.stylus.rawValue {
            updateStylusElement(page: page, usage: usage, intVal: intVal, logicalMax: logicalMax)
            scheduleFrameFlush()
            return
        }

        let device = IOHIDElementGetDevice(element)
        let devPtr = Unmanaged.passUnretained(device).toOpaque()
        let parentCookie = parent.map { IOHIDElementGetCookie($0) } ?? IOHIDElementGetCookie(element)
        let key = FingerSlotKey(device: devPtr, reportID: reportID, collectionCookie: parentCookie)

        var slot = fingerSlots[key] ?? FingerSlotState(slotID: Int(parentCookie))

        switch (page, usage) {
        case (HID.Page.digitizer.rawValue, HID.Digitizer.tipSwitch.rawValue):
            let touching = (intVal != 0)
            slot.tipSwitch = touching
            if !touching {
                slot.hasX = false
                slot.hasY = false
            }
            fingerSlots[key] = slot
            scheduleFrameFlush()

        case (HID.Page.genericDesktop.rawValue, HID.GenericDesktop.x.rawValue):
            slot.rawX = Double(intVal)
            slot.hasX = true
            if logicalMax > 100 { slot.maxX = logicalMax }
            fingerSlots[key] = slot
            if slot.tipSwitch {
                recordForAutoCalibration(x: Double(intVal))
            }
            scheduleFrameFlush()

        case (HID.Page.genericDesktop.rawValue, HID.GenericDesktop.y.rawValue):
            slot.rawY = Double(intVal)
            slot.hasY = true
            if logicalMax > 100 { slot.maxY = logicalMax }
            fingerSlots[key] = slot
            if slot.tipSwitch {
                recordForAutoCalibration(y: Double(intVal))
            }
            scheduleFrameFlush()

        default:
            break
        }
    }

    private func updateStylusElement(page: UInt32, usage: UInt32, intVal: CFIndex, logicalMax: Double) {
        switch (page, usage) {
        case (HID.Page.digitizer.rawValue, HID.Digitizer.tipSwitch.rawValue):
            stylusState.tipSwitch = (intVal != 0)
            stylusState.dirty = true
        case (HID.Page.digitizer.rawValue, HID.Digitizer.barrelSwitch.rawValue):
            stylusState.barrelSwitch = (intVal != 0)
            stylusState.dirty = true
        case (HID.Page.digitizer.rawValue, HID.Digitizer.secondaryBarrelSwitch.rawValue):
            stylusState.secondaryBarrelSwitch = (intVal != 0)
            stylusState.dirty = true
        case (HID.Page.digitizer.rawValue, HID.Digitizer.eraser.rawValue):
            stylusState.eraser = (intVal != 0)
            stylusState.dirty = true
        case (HID.Page.digitizer.rawValue, HID.Digitizer.invert.rawValue):
            stylusState.invert = (intVal != 0)
            stylusState.dirty = true
        case (HID.Page.digitizer.rawValue, HID.Digitizer.inRange.rawValue):
            stylusState.inRange = (intVal != 0)
            stylusState.dirty = true
        case (HID.Page.digitizer.rawValue, HID.Digitizer.tipPressure.rawValue):
            stylusState.rawPressure = Double(intVal)
            if logicalMax > 0 { stylusState.maxPressure = logicalMax }
            stylusState.dirty = true
        case (HID.Page.digitizer.rawValue, HID.Digitizer.xTilt.rawValue):
            let scale = logicalMax > 0 ? logicalMax : 90.0
            stylusState.tiltX = min(max(Double(intVal) / scale, -1.0), 1.0)
            stylusState.dirty = true
        case (HID.Page.digitizer.rawValue, HID.Digitizer.yTilt.rawValue):
            let scale = logicalMax > 0 ? logicalMax : 90.0
            stylusState.tiltY = min(max(Double(intVal) / scale, -1.0), 1.0)
            stylusState.dirty = true
        case (HID.Page.genericDesktop.rawValue, HID.GenericDesktop.x.rawValue):
            stylusState.rawX = Double(intVal)
            if logicalMax > 100 { stylusState.maxX = logicalMax }
            stylusState.dirty = true
        case (HID.Page.genericDesktop.rawValue, HID.GenericDesktop.y.rawValue):
            stylusState.rawY = Double(intVal)
            if logicalMax > 100 { stylusState.maxY = logicalMax }
            stylusState.dirty = true
        default:
            break
        }
    }

    private func scheduleFrameFlush() {
        guard !frameFlushScheduled else { return }
        frameFlushScheduled = true

        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue) { [weak self] in
            guard let self else { return }
            self.frameFlushScheduled = false
            self.flushCoalescedFrame()
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    private func flushCoalescedFrame() {
        let now = ProcessInfo.processInfo.systemUptime

        if let cur = currentDisplay, cur.isMain && !cur.isM14t {
            refreshTargetDisplay(logUpdate: true)
        }

        // 1. Flush Smart Pencil / Active Stylus if active
        if stylusState.dirty {
            stylusState.dirty = false
            let u = stylusState.maxX > 0 ? stylusState.rawX / stylusState.maxX : 0
            let v = stylusState.maxY > 0 ? stylusState.rawY / stylusState.maxY : 0
            let p = stylusState.maxPressure > 0 ? stylusState.rawPressure / stylusState.maxPressure : 0.5
            let sample = StylusSample(
                tipSwitch: stylusState.tipSwitch,
                barrelSwitch: stylusState.barrelSwitch,
                secondaryBarrelSwitch: stylusState.secondaryBarrelSwitch,
                eraser: stylusState.eraser,
                invert: stylusState.invert,
                inRange: stylusState.inRange,
                rawX: stylusState.rawX,
                rawY: stylusState.rawY,
                pressure: p,
                tiltX: stylusState.tiltX,
                tiltY: stylusState.tiltY,
                timestamp: now
            )
            let screenPt = mapper.mapNormalized(u: u, v: v)
            isTouchActive = sample.inRange || sample.isTipTouching
            if isTouchActive {
                recordTouchMovedCursorToExternal()
            }
            let actions = gestureEngine.processStylus(sample: sample, screenPoint: screenPt)
            if config.debugMode, !actions.isEmpty {
                log("✏️  stylus → \(actions)")
            }
            emitter.execute(actions)
            return
        }

        // 2. Collect all active finger slots (keyed by their distinct Finger collection cookie 2..6)
        let useCustomCalibration = config.autoCalibrate || config.hasManualCalibration || CalibrationStore.load() != nil
        var activeMapped: [MappedContact] = []

        let sortedSlots = fingerSlots.sorted { $0.key.collectionCookie < $1.key.collectionCookie }
        for (_, slot) in sortedSlots where slot.tipSwitch && (slot.hasX || slot.hasY || slot.rawX > 0 || slot.rawY > 0) {
            let screenPt: CGPoint
            if useCustomCalibration && abs(slot.maxX - HID.Hardware.touchMaxX) < 100 {
                screenPt = mapper.map(rawX: slot.rawX, rawY: slot.rawY)
            } else {
                let u = slot.maxX > 0 ? slot.rawX / slot.maxX : 0
                let v = slot.maxY > 0 ? slot.rawY / slot.maxY : 0
                screenPt = mapper.mapNormalized(u: u, v: v)
            }
            activeMapped.append(MappedContact(id: slot.slotID, point: screenPt))
        }

        guard !activeMapped.isEmpty || previousActiveFingerCount > 0 else { return }
        previousActiveFingerCount = activeMapped.count
        isTouchActive = !activeMapped.isEmpty
        if isTouchActive {
            recordTouchMovedCursorToExternal()
        }

        let actions = gestureEngine.processFrame(contacts: activeMapped, timestamp: now)
        if !actions.isEmpty {
            log("🖐️  fingers=\(activeMapped.count) → \(actions)")
        }
        emitter.execute(actions)
    }

    // MARK: - Hold Watchdog Timer

    private func startHoldWatchdog() {
        holdTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(40), repeating: .milliseconds(40))
        timer.setEventHandler { [weak self] in
            guard let self, self.isTouchActive else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let actions = self.gestureEngine.checkTimeouts(now: now)
            if !actions.isEmpty {
                self.log("⏱️  hold → \(actions)")
                self.emitter.execute(actions)
            }
        }
        self.holdTimer = timer
        timer.resume()
    }

    // MARK: - Cursor Auto-Return to Main Display

    public func updateConfig(_ newConfig: TouchConfig) {
        self.config = newConfig
        self.gestureEngine.config = newConfig
        self.mapper.invertX = newConfig.invertX
        self.mapper.invertY = newConfig.invertY
        if newConfig.returnCursorToMainDisplay {
            setupCursorAutoReturnTap()
        } else {
            tearDownCursorAutoReturnTap()
        }
    }

    private func setupCursorAutoReturnTap() {
        guard config.returnCursorToMainDisplay else {
            tearDownCursorAutoReturnTap()
            return
        }
        guard eventTap == nil else { return }
        guard isAccessibilityTrusted else { return }

        let mask: CGEventMask = (1 << CGEventType.mouseMoved.rawValue) |
                                (1 << CGEventType.leftMouseDown.rawValue) |
                                (1 << CGEventType.rightMouseDown.rawValue) |
                                (1 << CGEventType.otherMouseDown.rawValue) |
                                (1 << CGEventType.scrollWheel.rawValue) |
                                (1 << CGEventType.leftMouseDragged.rawValue) |
                                (1 << CGEventType.rightMouseDragged.rawValue) |
                                (1 << CGEventType.otherMouseDragged.rawValue)

        let context = Unmanaged.passUnretained(self).toOpaque()

        let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let driver = Unmanaged<HIDTouchDriver>.fromOpaque(refcon).takeUnretainedValue()
                return driver.handleGlobalMouseEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: context
        )

        guard let tap = tap else {
            log("⚠️  Could not create cursor auto-return event tap (check Accessibility permission)")
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.eventTapRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        CGEvent.tapEnable(tap: tap, enable: true)
        log("🔄 Pointer auto-return to main display enabled")
    }

    private func tearDownCursorAutoReturnTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = eventTapRunLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
                self.eventTapRunLoopSource = nil
            }
            self.eventTap = nil
        }
        cursorMovedByTouchToExternal = false
        lastMainDisplayPosition = nil
    }

    private func handleGlobalMouseEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Ignore synthetic events generated by our own driver
        if event.getIntegerValueField(.eventSourceUserData) == MouseEmitter.syntheticEventUserData {
            return Unmanaged.passUnretained(event)
        }

        // If touch or stylus is currently active, allow touch to proceed without interruption
        guard !isTouchActive else {
            return Unmanaged.passUnretained(event)
        }

        // Only return if cursor was specifically moved to external display by touch
        guard cursorMovedByTouchToExternal else {
            return Unmanaged.passUnretained(event)
        }

        let mainID = CGMainDisplayID()
        let mainBounds = CGDisplayBounds(mainID)

        // If pointer is already on main display, reset flag without jumping
        if mainBounds.contains(event.location) {
            cursorMovedByTouchToExternal = false
            lastMainDisplayPosition = nil
            return Unmanaged.passUnretained(event)
        }

        cursorMovedByTouchToExternal = false

        let targetPoint: CGPoint
        if let saved = lastMainDisplayPosition, mainBounds.contains(saved) {
            targetPoint = saved
        } else {
            targetPoint = CGPoint(x: mainBounds.midX, y: mainBounds.midY)
        }
        lastMainDisplayPosition = nil

        if config.debugMode {
            log("🎯 Auto-returning pointer to main display: \(targetPoint)")
        }

        CGWarpMouseCursorPosition(targetPoint)
        event.location = targetPoint

        return Unmanaged.passUnretained(event)
    }

    private func recordTouchMovedCursorToExternal() {
        guard config.returnCursorToMainDisplay else { return }
        guard let current = currentDisplay, !current.isMain else { return }

        if !cursorMovedByTouchToExternal {
            let mainID = CGMainDisplayID()
            let mainBounds = CGDisplayBounds(mainID)
            if let currentPos = currentCursorPosition(), mainBounds.contains(currentPos) {
                lastMainDisplayPosition = currentPos
            }
            cursorMovedByTouchToExternal = true
        }
    }

    private func currentCursorPosition() -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    // MARK: - Auto-calibration

    private func recordForAutoCalibration(x: Double? = nil, y: Double? = nil) {
        guard config.autoCalibrate else { return }
        if observed.update(x: x, y: y), let snapshot = observed.snapshot() {
            calibration = snapshot
            mapper.calibration = snapshot
            CalibrationStore.save(snapshot)
            log("🎯 Auto-cal: \(describe(snapshot))")
        }
    }

    private func describe(_ c: CalibrationData) -> String {
        "X \(Int(c.xMin))–\(Int(c.xMax))  Y \(Int(c.yMin))–\(Int(c.yMax))"
    }

    private func hex(_ value: Int) -> String { String(format: "%04X", value) }

    private func log(_ message: String) {
        print(message)
        fflush(stdout)
    }
}

// MARK: - Observed Range

struct ObservedRange {
    private var minX = Double.infinity
    private var maxX = -Double.infinity
    private var minY = Double.infinity
    private var maxY = -Double.infinity

    mutating func seed(with c: CalibrationData) {
        minX = c.xMin; maxX = c.xMax
        minY = c.yMin; maxY = c.yMax
    }

    mutating func update(x: Double?, y: Double?) -> Bool {
        var changed = false
        if let x, x >= 0 {
            if x < minX { minX = x; changed = true }
            if x > maxX { maxX = x; changed = true }
        }
        if let y, y >= 0 {
            if y < minY { minY = y; changed = true }
            if y > maxY { maxY = y; changed = true }
        }
        return changed
    }

    func snapshot() -> CalibrationData? {
        guard minX < maxX, minY < maxY else { return nil }
        return CalibrationData(xMin: minX, xMax: maxX, yMin: minY, yMax: maxY)
    }
}
