import ApplicationServices
import CoreGraphics
import Foundation

@_silgen_name("CGSGetSymbolicHotKeyValue")
private func CGSGetSymbolicHotKeyValue(
    _ hotKey: Int32,
    _ outKeyEquivalent: UnsafeMutablePointer<UniChar>,
    _ outVirtualKeyCode: UnsafeMutablePointer<UInt16>,
    _ outModifiers: UnsafeMutablePointer<UInt64>
) -> Int32

/// Synthesizes macOS pointer, click, drag/text-selection, 2-finger smooth scroll,
/// 2-finger pinch-zoom, and 3/4-finger Desktop/Spaces `CGEvent`s.
public final class MouseEmitter {

    private var activeClickCount: Int = 1

    // Inertial scroll momentum state
    private var lastScrollVelocityX: Double = 0
    private var lastScrollVelocityY: Double = 0
    private var momentumTimer: DispatchSourceTimer?

    public init() {}

    deinit {
        stopMomentum()
    }

    // MARK: - High-Level Action Execution

    public func execute(_ actions: [GestureAction]) {
        for action in actions {
            execute(action)
        }
    }

    public func execute(_ action: GestureAction) {
        switch action {
        case let .moveCursor(point):
            stopMomentum()
            postMouse(type: .mouseMoved, button: .left, at: point, clickCount: 0)

        case let .leftClick(point, clickCount):
            stopMomentum()
            let count = max(clickCount, 1)
            postMouse(type: .mouseMoved, button: .left, at: point, clickCount: 0)
            postMouse(type: .leftMouseDown, button: .left, at: point, clickCount: count)
            postMouse(type: .leftMouseUp, button: .left, at: point, clickCount: count)

        case let .leftMouseDown(point, clickCount):
            stopMomentum()
            activeClickCount = max(clickCount, 1)
            postMouse(type: .mouseMoved, button: .left, at: point, clickCount: 0)
            postMouse(type: .leftMouseDown, button: .left, at: point, clickCount: activeClickCount)

        case let .leftMouseDragged(point, pressure):
            stopMomentum()
            postMouse(type: .leftMouseDragged, button: .left, at: point, clickCount: activeClickCount, pressure: pressure)

        case let .leftMouseUp(point, clickCount):
            let count = max(clickCount, activeClickCount)
            postMouse(type: .leftMouseUp, button: .left, at: point, clickCount: count)
            activeClickCount = 1

        case let .rightClick(point):
            stopMomentum()
            postMouse(type: .mouseMoved, button: .left, at: point, clickCount: 0)
            postMouse(type: .rightMouseDown, button: .right, at: point, clickCount: 1)
            postMouse(type: .rightMouseUp, button: .right, at: point, clickCount: 1)

        case let .rightMouseDown(point):
            stopMomentum()
            postMouse(type: .mouseMoved, button: .left, at: point, clickCount: 0)
            postMouse(type: .rightMouseDown, button: .right, at: point, clickCount: 1)

        case let .rightMouseDragged(point):
            postMouse(type: .rightMouseDragged, button: .right, at: point, clickCount: 1)

        case let .rightMouseUp(point):
            postMouse(type: .rightMouseUp, button: .right, at: point, clickCount: 1)

        case let .middleClick(point):
            stopMomentum()
            postMouse(type: .mouseMoved, button: .left, at: point, clickCount: 0)
            postMouse(type: .otherMouseDown, button: .center, at: point, clickCount: 1)
            postMouse(type: .otherMouseUp, button: .center, at: point, clickCount: 1)

        case let .middleMouseDown(point):
            stopMomentum()
            postMouse(type: .mouseMoved, button: .left, at: point, clickCount: 0)
            postMouse(type: .otherMouseDown, button: .center, at: point, clickCount: 1)

        case let .middleMouseDragged(point):
            postMouse(type: .otherMouseDragged, button: .center, at: point, clickCount: 1)

        case let .middleMouseUp(point):
            postMouse(type: .otherMouseUp, button: .center, at: point, clickCount: 1)

        case let .scroll(point, deltaX, deltaY, phase):
            postScroll(at: point, deltaX: deltaX, deltaY: deltaY, phase: phase)

        case let .magnify(point, magnification, phase):
            stopMomentum()
            postMagnify(at: point, magnification: magnification, phase: phase)

        case let .systemGesture(gesture):
            stopMomentum()
            postSystemGesture(gesture)

        case let .tabletProximity(point, inRange, pointerType):
            postTabletProximity(at: point, inRange: inRange, pointerType: pointerType)

        case let .stylusHover(point, tiltX, tiltY, pointerType):
            stopMomentum()
            postStylusMouse(
                type: .mouseMoved,
                at: point,
                pressure: 0.0,
                tiltX: tiltX,
                tiltY: tiltY,
                pointerType: pointerType
            )

        case let .stylusDown(point, pressure, tiltX, tiltY, pointerType):
            stopMomentum()
            postStylusMouse(
                type: .mouseMoved,
                at: point,
                pressure: 0.0,
                tiltX: tiltX,
                tiltY: tiltY,
                pointerType: pointerType
            )
            postStylusMouse(
                type: .leftMouseDown,
                at: point,
                pressure: pressure,
                tiltX: tiltX,
                tiltY: tiltY,
                pointerType: pointerType
            )

        case let .stylusDragged(point, pressure, tiltX, tiltY, pointerType):
            stopMomentum()
            postStylusMouse(
                type: .leftMouseDragged,
                at: point,
                pressure: pressure,
                tiltX: tiltX,
                tiltY: tiltY,
                pointerType: pointerType
            )

        case let .stylusUp(point, pointerType):
            postStylusMouse(
                type: .leftMouseUp,
                at: point,
                pressure: 0.0,
                tiltX: 0.0,
                tiltY: 0.0,
                pointerType: pointerType
            )

        case .sendUndoShortcut:
            stopMomentum()
            postKeyShortcut(virtualKey: 6, flags: .maskCommand) // ⌘Z
        }
    }

    /// Direct mouse event poster (`mouseEventSource: nil` so macOS WindowServer
    /// always shows and moves the visible cursor arrow without suppression).
    public func post(_ type: CGEventType, at point: CGPoint) {
        let button: CGMouseButton = (type == .rightMouseDown || type == .rightMouseUp || type == .rightMouseDragged) ? .right : .left
        postMouse(type: type, button: button, at: point, clickCount: 1)
    }

    // MARK: - Pointer & Selection Synthesis

    private func postMouse(
        type: CGEventType,
        button: CGMouseButton,
        at point: CGPoint,
        clickCount: Int,
        pressure: Double = 1.0
    ) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: button
        ) else {
            FileHandle.standardError.write(
                Data("⚠️  CGEvent creation failed — is Accessibility permission granted?\n".utf8)
            )
            return
        }

        if clickCount > 0 {
            event.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        }
        if type == .leftMouseDragged || type == .leftMouseDown {
            event.setDoubleValueField(.mouseEventPressure, value: pressure)
        }
        event.post(tap: .cghidEventTap)
    }

    // MARK: - Native Wacom / Smart Pencil Tablet Event Synthesis

    private func postTabletProximity(at point: CGPoint, inRange: Bool, pointerType: StylusPointerType) {
        guard let event = CGEvent(source: nil) else { return }
        event.type = .tabletProximity
        event.location = point
        event.setIntegerValueField(.tabletProximityEventEnterProximity, value: inRange ? 1 : 0)
        event.setIntegerValueField(.tabletProximityEventPointerType, value: Int64(pointerType.rawValue))
        event.setIntegerValueField(.tabletProximityEventVendorID, value: 0x056A) // Wacom
        event.setIntegerValueField(.tabletProximityEventCapabilityMask, value: 0x07FF)
        event.post(tap: .cghidEventTap)
    }

    private func postStylusMouse(
        type: CGEventType,
        at point: CGPoint,
        pressure: Double,
        tiltX: Double,
        tiltY: Double,
        pointerType: StylusPointerType
    ) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            return
        }

        // kCGEventMouseSubtypeTabletPoint = 1
        event.setIntegerValueField(.mouseEventSubtype, value: 1)
        if type == .leftMouseDown || type == .leftMouseUp || type == .leftMouseDragged {
            event.setIntegerValueField(.mouseEventClickState, value: 1)
        }
        event.setDoubleValueField(.mouseEventPressure, value: pressure)
        event.setDoubleValueField(.tabletEventPointPressure, value: pressure)
        event.setDoubleValueField(.tabletEventTiltX, value: tiltX)
        event.setDoubleValueField(.tabletEventTiltY, value: tiltY)
        event.setIntegerValueField(.tabletProximityEventPointerType, value: Int64(pointerType.rawValue))
        event.post(tap: .cghidEventTap)
    }

    private func postKeyShortcut(virtualKey: CGKeyCode, flags: CGEventFlags) {
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: false) else {
            return
        }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    // MARK: - Smooth 2D Trackpad Scroll + High-Frequency Inertial Momentum

    private var scrollAccumulatorX: Double = 0
    private var scrollAccumulatorY: Double = 0

    private func postScroll(at point: CGPoint, deltaX: Double, deltaY: Double, phase: GesturePhase) {
        switch phase {
        case .began:
            stopMomentum()
            scrollAccumulatorX = 0
            scrollAccumulatorY = 0
            lastScrollVelocityX = 0
            lastScrollVelocityY = 0
            postMouse(type: .mouseMoved, button: .left, at: point, clickCount: 0)
            emitScrollPacket(at: point, dx: 0, dy: 0, scrollPhase: phase.rawValue, momentumPhase: 0)

        case .changed:
            lastScrollVelocityX = 0.5 * deltaX + 0.5 * lastScrollVelocityX
            lastScrollVelocityY = 0.5 * deltaY + 0.5 * lastScrollVelocityY
            emitScrollPacket(at: point, dx: deltaX, dy: deltaY, scrollPhase: phase.rawValue, momentumPhase: 0)

        case .ended, .cancelled:
            emitScrollPacket(at: point, dx: 0, dy: 0, scrollPhase: phase.rawValue, momentumPhase: 0)
            startMomentumIfNeeded(at: point, vx: lastScrollVelocityX, vy: lastScrollVelocityY)
        }
    }

    private func emitScrollPacket(
        at point: CGPoint,
        dx: Double,
        dy: Double,
        scrollPhase: UInt64,
        momentumPhase: UInt64
    ) {
        scrollAccumulatorX += dx
        scrollAccumulatorY += dy
        let intDX = Int32(scrollAccumulatorX)
        let intDY = Int32(scrollAccumulatorY)
        scrollAccumulatorX -= Double(intDX)
        scrollAccumulatorY -= Double(intDY)

        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: intDY,
            wheel2: intDX,
            wheel3: 0
        ) else { return }

        event.location = point
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(intDY))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(intDX))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: dy)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: dx)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(scrollPhase))
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(momentumPhase))
        event.post(tap: .cghidEventTap)
    }

    private func startMomentumIfNeeded(at point: CGPoint, vx: Double, vy: Double) {
        stopMomentum()
        guard hypot(vx, vy) >= 2.0 else { return }

        var curVX = vx
        var curVY = vy
        var isFirstTick = true

        let timer = DispatchSource.makeTimerSource(queue: .main)
        // 8ms timer (~125 Hz) produces butter-smooth frame pacing on 60Hz and 75Hz panels
        timer.schedule(deadline: .now() + .milliseconds(8), repeating: .milliseconds(8))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if hypot(curVX, curVY) < 0.35 {
                self.emitScrollPacket(at: point, dx: 0, dy: 0, scrollPhase: 0, momentumPhase: 4)
                self.stopMomentum()
                return
            }
            let mPhase: UInt64 = isFirstTick ? 1 : 2
            isFirstTick = false
            self.emitScrollPacket(at: point, dx: curVX * 0.5, dy: curVY * 0.5, scrollPhase: 0, momentumPhase: mPhase)
            curVX *= 0.965
            curVY *= 0.965
        }
        self.momentumTimer = timer
        timer.resume()
    }

    private func stopMomentum() {
        momentumTimer?.cancel()
        momentumTimer = nil
        scrollAccumulatorX = 0
        scrollAccumulatorY = 0
    }

    // MARK: - Native Trackpad Pinch-to-Zoom (`NSEvent.EventType.magnify`)

    private func postMagnify(at point: CGPoint, magnification: Double, phase: GesturePhase) {
        guard let gestureType = CGEventType(rawValue: 29),
              let zoomEvent = CGEvent(source: nil),
              let dockWrapper = CGEvent(source: nil) else { return }

        if phase == .began {
            postMouse(type: .mouseMoved, button: .left, at: point, clickCount: 0)
        }

        zoomEvent.type = gestureType
        zoomEvent.location = point
        if let f110 = CGEventField(rawValue: 110) { zoomEvent.setIntegerValueField(f110, value: 8) }
        if let f113 = CGEventField(rawValue: 113) { zoomEvent.setDoubleValueField(f113, value: magnification) }
        if let f114 = CGEventField(rawValue: 114) { zoomEvent.setDoubleValueField(f114, value: magnification) }
        if let f116 = CGEventField(rawValue: 116) { zoomEvent.setDoubleValueField(f116, value: magnification) }
        if let f132 = CGEventField(rawValue: 132) { zoomEvent.setIntegerValueField(f132, value: Int64(phase.rawValue)) }

        dockWrapper.type = gestureType
        dockWrapper.location = point
        if let f110 = CGEventField(rawValue: 110) { dockWrapper.setIntegerValueField(f110, value: 61) }
        if let f132 = CGEventField(rawValue: 132) { dockWrapper.setIntegerValueField(f132, value: Int64(phase.rawValue)) }

        zoomEvent.post(tap: .cghidEventTap)
        dockWrapper.post(tap: .cghidEventTap)
    }

    // MARK: - System Trackpad Shortcuts (Desktops / Spaces, Mission Control, App Exposé)

    private func postSystemGesture(_ gesture: SystemTrackpadGesture) {
        let (hotKeyID, fallbackVK, fallbackMods): (Int32, CGKeyCode, CGEventFlags) = {
            switch gesture {
            case .spaceLeft:
                return (79, 123, [.maskControl, .maskSecondaryFn])
            case .spaceRight:
                return (81, 124, [.maskControl, .maskSecondaryFn])
            case .missionControl:
                return (32, 126, [.maskControl, .maskSecondaryFn])
            case .appExpose:
                return (33, 125, [.maskControl, .maskSecondaryFn])
            case .showDesktop:
                return (36, 103, [.maskSecondaryFn])
            }
        }()

        var keyEquiv: UniChar = 0
        var virtualKey: UInt16 = 0
        var rawModifiers: UInt64 = 0
        let status = CGSGetSymbolicHotKeyValue(hotKeyID, &keyEquiv, &virtualKey, &rawModifiers)

        let keyCode: CGKeyCode
        let flags: CGEventFlags
        if status == 0, virtualKey != 0xFFFF {
            keyCode = CGKeyCode(virtualKey)
            flags = CGEventFlags(rawValue: rawModifiers)
        } else {
            keyCode = fallbackVK
            flags = fallbackMods
        }

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return
        }

        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
