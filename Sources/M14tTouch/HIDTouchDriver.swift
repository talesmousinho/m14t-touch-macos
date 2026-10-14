import IOKit.hid
import CoreGraphics
import Foundation

/// Bridges the M14t's USB HID touch interface to the macOS cursor.
///
/// Responsibilities are deliberately narrow: open the HID device, translate the
/// raw touch stream into screen coordinates (via `CoordinateMapper`), and emit
/// mouse events (via `MouseEmitter`). Calibration math and event posting live in
/// their own types, so this file is purely about *orchestration* and the touch
/// state machine.
///
/// ## Touch model
/// A single contact maps directly to the left mouse button:
/// - finger down  → `leftMouseDown`
/// - finger moves → `leftMouseDragged` (only past the jitter threshold)
/// - finger up    → `leftMouseUp`
///
/// A down-then-up with no movement is a normal click; a down-move-up is a drag.
/// Opt-in Gen 1 scrolling uses complete reports and TouchGestures instead of
/// the default per-element state machine.
final class HIDTouchDriver {

    private var config: TouchConfig
    private let emitter = MouseEmitter()

    // IOKit
    private var manager: IOHIDManager?

    // Coordinate state
    private var calibration: CalibrationData
    private var mapper: CoordinateMapper
    private var target: DisplayTarget
    private var displayTimer: Timer?
    private var waitForTouchRelease = false

    // Auto-calibration: the tightest range observed so far
    private var observed = ObservedRange()

    // Current touch sample and contact state
    private var currentRawX: Double = 0
    private var currentRawY: Double = 0
    private var isTouching = false
    private var lastScreenPoint: CGPoint = .zero
    private var gestures = TouchGestures()
    private var frameContacts: [TouchContact] = []
    private var gestureTimer: Timer?
    private var scrollRemainder = CGPoint.zero
    private var shutdownSignals: [DispatchSourceSignal] = []

    init(config: TouchConfig) {
        self.config = config

        // Provisional calibration; refined once the device is connected.
        let initial = CalibrationData.identity
        self.calibration = initial

        let target = DisplayTarget(index: config.displayIndex, uuid: config.displayUUID,
                                   displays: DisplayResolver.all())
        self.target = target
        self.mapper = CoordinateMapper(
            calibration: initial,
            displayBounds: target.current?.bounds ?? .zero,
            invertX: config.invertX,
            invertY: config.invertY
        )
    }

    // MARK: - Lifecycle

    /// Open the HID manager and begin listening. Blocks via the caller's run loop.
    func start() {
        guard target.uuid != nil else {
            log("❌ Selected display is unavailable. Use --list to select the M14t.")
            exit(1)
        }
        logTarget()
        // Refresh even when no HID reports arrive, so held buttons are released
        // on disconnect. Input and pending-press paths also refresh immediately.
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.refreshDisplay()
        }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        var matching: [String: Int] = [
            kIOHIDDeviceUsagePageKey: HID.Page.digitizer.rawValue,
            kIOHIDDeviceUsageKey:     HID.Digitizer.touchScreen.rawValue
        ].mapValues { Int($0) }
        if config.twoFingerScroll {
            // The raw report layout is specific to this Gen 1 controller.
            // Preserve the existing usage-based match for default mode.
            matching[kIOHIDVendorIDKey] = 0x2d1f
            matching[kIOHIDProductIDKey] = 0x524c
        }
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
            HIDTouchDriver.from(ctx).deviceConnected(device)
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, _ in
            HIDTouchDriver.from(ctx).deviceRemoved()
        }, context)

        if config.twoFingerScroll {
            IOHIDManagerRegisterInputReportCallback(manager, { ctx, result, _, _, reportID, report, length in
                guard result == kIOReturnSuccess else { return }
                HIDTouchDriver.from(ctx).handleReport(reportID: reportID,
                    bytes: Array(UnsafeBufferPointer(start: report, count: length)))
            }, context)
            // A held finger must turn into a drag even if the HID device stops
            // sending unchanged frames. Only pending presses need timer work.
            gestureTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
                guard let self, self.gestures.isPending else { return }
                self.refreshDisplay()
                guard self.target.current != nil, self.gestures.isPending else { return }
                self.emit(self.gestures.update(self.frameContacts, at: ProcessInfo.processInfo.systemUptime))
            }
            log("✌️  Two-finger scrolling ON — lift both fingers before starting a new gesture")
        } else {
            IOHIDManagerRegisterInputValueCallback(manager, { ctx, _, _, value in
                HIDTouchDriver.from(ctx).handle(value)
            }, context)
        }

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnSuccess {
            log("✅ Listening for touch device…")
        } else {
            log("❌ Could not open HID manager (code \(result))")
            log("   Grant 'Input Monitoring' in System Settings → Privacy & Security, then retry.")
        }
        for signalNumber in [SIGTERM, SIGINT] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak self] in
                self?.deviceRemoved()
                exit(0)
            }
            source.resume()
            shutdownSignals.append(source)
        }
    }

    /// Recover `self` from the opaque pointer passed to C callbacks.
    private static func from(_ ctx: UnsafeMutableRawPointer?) -> HIDTouchDriver {
        Unmanaged<HIDTouchDriver>.fromOpaque(ctx!).takeUnretainedValue()
    }

    // MARK: - Display tracking

    private func logTarget() {
        if let display = target.current {
            let bounds = display.bounds
            log("🖥️  Target \(display.uuid) [\(display.index)]: \(Int(bounds.width))×\(Int(bounds.height)) @ (\(Int(bounds.minX)),\(Int(bounds.minY)))")
        } else {
            log("⏸️  Target display \(target.uuid ?? "unknown") disconnected; touch input paused")
        }
    }

    private func refreshDisplay() {
        guard target.refresh(DisplayResolver.all()) else { return }
        // A pending press or scroll anchor belongs to the old coordinate space.
        // An interrupted gesture must lift completely before it can restart.
        if !frameContacts.isEmpty { emit(gestures.interrupt()) }
        frameContacts = []
        scrollRemainder = .zero
        if isTouching {
            emitter.post(.leftMouseUp, at: lastScreenPoint)
            isTouching = false
            waitForTouchRelease = true
        }
        mapper.displayBounds = target.current?.bounds ?? .zero
        logTarget()
    }

    // MARK: - Device Callbacks

    private func deviceConnected(_ device: IOHIDDevice) {
        let name    = IOHIDDeviceGetProperty(device, kIOHIDProductKey   as CFString) as? String ?? "Unknown"
        let vendor  = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey  as CFString) as? Int ?? 0
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        log("🔌 Connected: \"\(name)\"  VID 0x\(hex(vendor))  PID 0x\(hex(product))")

        resolveCalibration(for: device)
    }

    private func deviceRemoved() {
        log("🔌 Touch device disconnected")
        frameContacts = []
        emit(gestures.cancel())
        // Release any held button so the cursor doesn't get stuck pressed.
        if isTouching {
            emitter.post(.leftMouseUp, at: lastScreenPoint)
            isTouching = false
        }
    }

    // MARK: - Calibration Resolution
    //
    // Precedence: manual flags > saved file > HID descriptor.

    private func resolveCalibration(for device: IOHIDDevice) {
        var resolved = readDescriptorRange(from: device)

        if let saved = CalibrationStore.load(), !config.hasManualCalibration, !config.autoCalibrate {
            resolved = saved
            observed.seed(with: saved)
            log("💾 Loaded calibration: \(describe(resolved))")
        }

        // Manual overrides take ultimate priority.
        if let v = config.manualXMin { resolved.xMin = v }
        if let v = config.manualXMax { resolved.xMax = v }
        if let v = config.manualYMin { resolved.yMin = v }
        if let v = config.manualYMax { resolved.yMax = v }
        if config.hasManualCalibration {
            log("📐 Manual calibration: \(describe(resolved))")
        }

        calibration = resolved
        mapper.calibration = resolved

        if config.autoCalibrate {
            log("🎯 Auto-calibrate ON — learning fresh bounds; touch all four corners of the screen")
        }
    }

    /// Read the logical X/Y range the device advertises in its HID descriptor.
    private func readDescriptorRange(from device: IOHIDDevice) -> CalibrationData {
        var range = CalibrationData.identity
        guard let elements = IOHIDDeviceCopyMatchingElements(
            device, nil, IOOptionBits(kIOHIDOptionsTypeNone)
        ) as? [IOHIDElement] else { return range }

        for element in elements where IOHIDElementGetUsagePage(element) == HID.Page.genericDesktop.rawValue {
            switch IOHIDElementGetUsage(element) {
            case HID.GenericDesktop.x.rawValue:
                range.xMin = Double(IOHIDElementGetLogicalMin(element))
                range.xMax = Double(IOHIDElementGetLogicalMax(element))
            case HID.GenericDesktop.y.rawValue:
                range.yMin = Double(IOHIDElementGetLogicalMin(element))
                range.yMax = Double(IOHIDElementGetLogicalMax(element))
            default:
                break
            }
        }
        log("📐 Descriptor range: \(describe(range))")
        return range
    }

    // MARK: - Input Handling

    private func handleReport(reportID: UInt32, bytes: [UInt8]) {
        // Both digitizer interfaces enumerate. Only report 0x0c carries the
        // five simultaneous Gen 1 contacts; ignore the pen/secondary interface.
        guard reportID == 0x0c else { return }
        refreshDisplay()
        guard let rawContacts = M14tReport.decode(bytes) else {
            if config.debugMode { log("HID rejected report 0x0C length=\(bytes.count) bytes=\(bytes.prefix(12))") }
            frameContacts = []
            emit(gestures.interrupt())
            return
        }
        if config.debugMode {
            log("HID frame 0x0C contacts=\(rawContacts.count) " + rawContacts.map {
                "id=\($0.id) x=\(Int($0.point.x)) y=\(Int($0.point.y))"
            }.joined(separator: " | "))
        }
        guard target.current != nil else {
            frameContacts = []
            emit(gestures.update(rawContacts, at: ProcessInfo.processInfo.systemUptime, inputEnabled: false))
            return
        }
        if config.autoCalibrate {
            for contact in rawContacts { recordForAutoCalibration(x: contact.point.x, y: contact.point.y) }
        }
        frameContacts = rawContacts.map {
            TouchContact(id: $0.id, point: mapper.map(rawX: $0.point.x, rawY: $0.point.y))
        }
        emit(gestures.update(frameContacts, at: ProcessInfo.processInfo.systemUptime))
    }

    private func emit(_ actions: [TouchAction]) {
        for action in actions {
            switch action {
            case .move(let point):
                scrollRemainder = .zero
                emitter.post(.mouseMoved, at: point)
            case .down(let point): emitter.post(.leftMouseDown, at: point)
            case .drag(let point): emitter.post(.leftMouseDragged, at: point)
            case .up(let point): emitter.post(.leftMouseUp, at: point)
            case .scroll(let point, let dx, let dy):
                scrollRemainder.x += dx
                scrollRemainder.y += dy
                let x = Int32(scrollRemainder.x.rounded(.towardZero))
                let y = Int32(scrollRemainder.y.rounded(.towardZero))
                scrollRemainder.x -= Double(x)
                scrollRemainder.y -= Double(y)
                if x != 0 || y != 0 { emitter.scroll(at: point, dx: x, dy: y) }
            }
            if config.debugMode { log("GESTURE \(action)") }
        }
    }

    private func handle(_ value: IOHIDValue) {
        refreshDisplay()
        let element = IOHIDValueGetElement(value)
        let page    = IOHIDElementGetUsagePage(element)
        let usage   = IOHIDElementGetUsage(element)
        let intVal  = IOHIDValueGetIntegerValue(value)
        guard target.current != nil else {
            if page == HID.Page.digitizer.rawValue && usage == HID.Digitizer.tipSwitch.rawValue {
                waitForTouchRelease = intVal != 0
            }
            return
        }

        if config.debugMode {
            log("HID  page=0x\(hex(Int(page)))  usage=0x\(hex(Int(usage)))  val=\(intVal)")
        }

        switch (page, usage) {

        case (HID.Page.genericDesktop.rawValue, HID.GenericDesktop.x.rawValue):
            currentRawX = Double(intVal)
            recordForAutoCalibration(x: Double(intVal))
            emitDragIfMoved()

        case (HID.Page.genericDesktop.rawValue, HID.GenericDesktop.y.rawValue):
            currentRawY = Double(intVal)
            recordForAutoCalibration(y: Double(intVal))
            emitDragIfMoved()

        case (HID.Page.digitizer.rawValue, HID.Digitizer.tipSwitch.rawValue):
            updateContact(touching: intVal != 0)

        default:
            break
        }
    }

    /// Finger made or broke contact with the surface.
    private func updateContact(touching: Bool) {
        if waitForTouchRelease {
            if !touching { waitForTouchRelease = false }
            return
        }
        if touching, !isTouching {
            isTouching = true
            lastScreenPoint = mapper.map(rawX: currentRawX, rawY: currentRawY)
            emitter.post(.leftMouseDown, at: lastScreenPoint)
            log("☝️  DOWN  → (\(Int(lastScreenPoint.x)),\(Int(lastScreenPoint.y)))")
        } else if !touching, isTouching {
            isTouching = false
            emitter.post(.leftMouseUp, at: lastScreenPoint)
            log("☝️  UP    → (\(Int(lastScreenPoint.x)),\(Int(lastScreenPoint.y)))")
        }
    }

    /// While a finger is down, translate position changes into drag events.
    private func emitDragIfMoved() {
        guard isTouching else { return }
        let point = mapper.map(rawX: currentRawX, rawY: currentRawY)
        let moved = abs(point.x - lastScreenPoint.x) > config.dragThreshold
                 || abs(point.y - lastScreenPoint.y) > config.dragThreshold
        guard moved else { return }

        emitter.post(.leftMouseDragged, at: point)
        lastScreenPoint = point
        log("☝️  DRAG  → (\(Int(point.x)),\(Int(point.y)))")
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

    // MARK: - Helpers

    private func describe(_ c: CalibrationData) -> String {
        "X \(Int(c.xMin))–\(Int(c.xMax))  Y \(Int(c.yMin))–\(Int(c.yMax))"
    }

    private func hex(_ value: Int) -> String { String(format: "%04X", value) }

    private func log(_ message: String) { print(message) }
}

// MARK: - Observed Range

/// Tracks the tightest min/max coordinates seen during auto-calibration.
struct ObservedRange {
    private var minX = Double.infinity
    private var maxX = -Double.infinity
    private var minY = Double.infinity
    private var maxY = -Double.infinity

    /// Seed from a previously-saved calibration so auto-cal refines rather than
    /// starting from nothing.
    mutating func seed(with c: CalibrationData) {
        minX = c.xMin; maxX = c.xMax
        minY = c.yMin; maxY = c.yMax
    }

    /// Feed a new sample. Returns `true` if the range expanded.
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

    /// A valid calibration, or `nil` if the range hasn't formed yet.
    func snapshot() -> CalibrationData? {
        guard minX < maxX, minY < maxY else { return nil }
        return CalibrationData(xMin: minX, xMax: maxX, yMin: minY, yMax: maxY)
    }
}
