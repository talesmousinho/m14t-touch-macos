import CoreGraphics
import Foundation

/// Lifecycle phase of a continuous trackpad gesture (scroll or magnify).
public enum GesturePhase: UInt64, Equatable, Sendable {
    case began     = 1
    case changed   = 2
    case ended     = 4
    case cancelled = 8
}

/// System-wide macOS multi-finger trackpad shortcuts.
public enum SystemTrackpadGesture: String, Equatable, Sendable {
    case spaceLeft
    case spaceRight
    case missionControl
    case appExpose
    case showDesktop
}

/// macOS tablet transducer pointer type (`NSPointingDeviceType` raw values).
public enum StylusPointerType: UInt64, Equatable, Sendable {
    case pen    = 1
    case eraser = 3
}

/// High-level action emitted by `GestureEngine` and executed by `MouseEmitter`.
public enum GestureAction: Equatable, Sendable {
    case moveCursor(to: CGPoint)
    case leftClick(at: CGPoint, clickCount: Int)
    case leftMouseDown(at: CGPoint, clickCount: Int)
    case leftMouseDragged(to: CGPoint, pressure: Double)
    case leftMouseUp(at: CGPoint, clickCount: Int)
    case rightClick(at: CGPoint)
    case rightMouseDown(at: CGPoint)
    case rightMouseDragged(to: CGPoint)
    case rightMouseUp(at: CGPoint)
    case middleClick(at: CGPoint)
    case middleMouseDown(at: CGPoint)
    case middleMouseDragged(to: CGPoint)
    case middleMouseUp(at: CGPoint)
    case scroll(at: CGPoint, deltaX: Double, deltaY: Double, phase: GesturePhase)
    case magnify(at: CGPoint, magnification: Double, phase: GesturePhase)
    case systemGesture(SystemTrackpadGesture)
    case tabletProximity(at: CGPoint, inRange: Bool, pointerType: StylusPointerType)
    case stylusHover(to: CGPoint, tiltX: Double, tiltY: Double, pointerType: StylusPointerType)
    case stylusDown(at: CGPoint, pressure: Double, tiltX: Double, tiltY: Double, pointerType: StylusPointerType)
    case stylusDragged(to: CGPoint, pressure: Double, tiltX: Double, tiltY: Double, pointerType: StylusPointerType)
    case stylusUp(at: CGPoint, pointerType: StylusPointerType)
    case sendUndoShortcut
}

/// Screen-mapped finger contact passed into `GestureEngine`.
public struct MappedContact: Equatable, Sendable {
    public let id: Int
    public let point: CGPoint

    public init(id: Int, point: CGPoint) {
        self.id = id
        self.point = point
    }
}

/// Pure, deterministic state machine translating multi-touch and stylus frames
/// into tablet pointer actions and MacBook trackpad gestures.
public final class GestureEngine {

    public var config: TouchConfig

    private enum State: Equatable {
        case idle
        case oneFingerPending(
            id: Int,
            startPoint: CGPoint,
            lastPoint: CGPoint,
            startTime: TimeInterval,
            clickCount: Int
        )
        case oneFingerDragging(
            id: Int,
            lastPoint: CGPoint,
            clickCount: Int
        )
        case oneFingerScrolling(
            id: Int,
            lastPoint: CGPoint
        )
        case twoFingerPending(
            startCentroid: CGPoint,
            lastCentroid: CGPoint,
            startSpan: Double,
            lastSpan: Double,
            startTime: TimeInterval
        )
        case twoFingerScrolling(
            lastCentroid: CGPoint,
            lastSpan: Double
        )
        case twoFingerPinching(
            lastCentroid: CGPoint,
            startSpan: Double,
            lastSpan: Double
        )
        case multiFingerPending(
            fingerCount: Int,
            startCentroid: CGPoint,
            lastCentroid: CGPoint,
            startSpan: Double,
            startTime: TimeInterval
        )
        case waitingForLift
    }

    private var state: State = .idle

    // Multi-tap (double-click / triple-click) tracking
    private var lastTapTime: TimeInterval = -100
    private var lastTapPoint: CGPoint = .zero
    private var consecutiveTapCount: Int = 0

    // Active stylus (Smart Pencil) state
    public private(set) var isStylusInRange = false
    private var activeStylusPointerType: StylusPointerType = .pen
    private var isStylusTipDown = false
    private var isStylusRightDown = false
    private var isStylusMiddleDown = false
    private var wasBarrelPressed = false
    private var wasTopButtonPressed = false
    private var lastStylusPoint: CGPoint = .zero
    private var lastStylusTimestamp: TimeInterval = 0

    // Threshold constants (in macOS screen points & seconds)
    private let tapMaxDuration: TimeInterval = 1.20
    private let doubleTapMaxInterval: TimeInterval = 0.35
    private let doubleTapMaxDistance: Double = 28.0
    private let tapSlop: Double = 14.0
    private let multiFingerGraceInterval: TimeInterval = 0.055
    private let twoFingerTapMaxDuration: TimeInterval = 0.40
    private let twoFingerTapSlop: Double = 15.0
    private let twoFingerTapMaxSpanChange: Double = 32.0
    private let scrollStartThreshold: Double = 15.0
    private let pinchStartThreshold: Double = 26.0
    private let threeFingerSwipeThreshold: Double = 52.0
    private let holdToSelectDuration: TimeInterval = 0.24

    public init(config: TouchConfig = TouchConfig()) {
        self.config = config
    }

    // MARK: - Multi-Touch Frame Processing

    public func processFrame(contacts: [MappedContact], timestamp: TimeInterval) -> [GestureAction] {
        var actions: [GestureAction] = []

        // First evaluate any time-based transitions up to `timestamp`.
        actions.append(contentsOf: checkTimeouts(now: timestamp))

        let count = contacts.count

        if count == 0 {
            actions.append(contentsOf: handleAllFingersLifted(timestamp: timestamp))
            return actions
        }

        switch count {
        case 1:
            actions.append(contentsOf: handleOneFinger(contacts[0], timestamp: timestamp))
        case 2:
            actions.append(contentsOf: handleTwoFingers(contacts[0], contacts[1], timestamp: timestamp))
        default:
            actions.append(contentsOf: handleMultiFingers(contacts, timestamp: timestamp))
        }

        return actions
    }

    /// Evaluates stationary hold timers (optional long-press right-click or hold-to-select in iPad scroll mode).
    public func checkTimeouts(now: TimeInterval) -> [GestureAction] {
        guard case let .oneFingerPending(id, startPoint, lastPoint, startTime, clickCount) = state else {
            return []
        }

        let elapsed = now - startTime
        let moved = hypot(lastPoint.x - startPoint.x, lastPoint.y - startPoint.y)
        guard moved <= max(tapSlop, config.dragThreshold * 2.0) else { return [] }

        if config.longPressRightClick && elapsed >= config.longPressDuration {
            state = .waitingForLift
            consecutiveTapCount = 0
            return [.rightClick(at: startPoint)]
        }

        if config.oneFingerMode == .scrollAndHoldToSelect && !config.longPressRightClick && elapsed >= holdToSelectDuration {
            state = .oneFingerDragging(id: id, lastPoint: lastPoint, clickCount: clickCount)
            return [.leftMouseDown(at: startPoint, clickCount: clickCount)]
        }

        return []
    }

    /// Reset all active gestures (e.g. on device disconnect).
    public func reset() -> [GestureAction] {
        var actions = cancelFingerGestureForStylus()
        if isStylusTipDown {
            actions.append(.leftMouseUp(at: lastStylusPoint, clickCount: 1))
            isStylusTipDown = false
        }
        if isStylusRightDown {
            actions.append(.rightMouseUp(at: lastStylusPoint))
            isStylusRightDown = false
        }
        if isStylusMiddleDown {
            actions.append(.middleMouseUp(at: lastStylusPoint))
            isStylusMiddleDown = false
        }
        wasBarrelPressed = false
        wasTopButtonPressed = false
        return actions
    }

    private func cancelFingerGestureForStylus() -> [GestureAction] {
        var actions: [GestureAction] = []
        switch state {
        case let .oneFingerDragging(_, lastPoint, clickCount):
            actions.append(.leftMouseUp(at: lastPoint, clickCount: clickCount))
        case let .oneFingerScrolling(_, lastPoint):
            actions.append(.scroll(at: lastPoint, deltaX: 0, deltaY: 0, phase: .ended))
        case let .twoFingerScrolling(lastCentroid, _):
            actions.append(.scroll(at: lastCentroid, deltaX: 0, deltaY: 0, phase: .ended))
        case let .twoFingerPinching(lastCentroid, _, _):
            actions.append(.magnify(at: lastCentroid, magnification: 0, phase: .ended))
        default:
            break
        }
        state = .idle
        return actions
    }

    // MARK: - Smart Pencil / Active Stylus Processing

    public func processStylus(sample: StylusSample, screenPoint: CGPoint) -> [GestureAction] {
        guard config.stylusEnabled else { return [] }
        var actions: [GestureAction] = []
        lastStylusPoint = screenPoint

        let barrelActive = sample.barrelSwitch && config.barrelButtonAction != .disabled
        let topButtonActive = sample.isTopButtonActive && config.secondaryBarrelButtonAction != .disabled
        let anyActiveSignal = sample.inRange || sample.isTipTouching || barrelActive || topButtonActive

        // 1. Handle pen leaving digitizer proximity range
        if !anyActiveSignal {
            if isStylusTipDown {
                isStylusTipDown = false
                actions.append(.leftMouseUp(at: screenPoint, clickCount: 1))
            }
            if isStylusRightDown {
                isStylusRightDown = false
                actions.append(.rightMouseUp(at: screenPoint))
            }
            if isStylusMiddleDown {
                isStylusMiddleDown = false
                actions.append(.middleMouseUp(at: screenPoint))
            }
            wasBarrelPressed = false
            wasTopButtonPressed = false
            return actions
        }

        // 2. Evaluate one-shot barrel button actions (Double-Click, Undo) on rising edge
        let barrelRisingEdge = barrelActive && !wasBarrelPressed
        let topRisingEdge = topButtonActive && !wasTopButtonPressed
        wasBarrelPressed = barrelActive
        wasTopButtonPressed = topButtonActive

        if barrelRisingEdge {
            switch config.barrelButtonAction {
            case .doubleClick:
                actions.append(.leftClick(at: screenPoint, clickCount: 2))
                return actions
            case .undo:
                actions.append(.sendUndoShortcut)
                return actions
            default:
                break
            }
        }

        if topRisingEdge {
            switch config.secondaryBarrelButtonAction {
            case .doubleClick:
                actions.append(.leftClick(at: screenPoint, clickCount: 2))
                return actions
            case .undo:
                actions.append(.sendUndoShortcut)
                return actions
            default:
                break
            }
        }

        // 3. Evaluate continuous held barrel button actions (Right-Click / Drag, Middle-Click / Drag)
        let wantsRightHold =
            (barrelActive && config.barrelButtonAction == .rightClick) ||
            (topButtonActive && config.secondaryBarrelButtonAction == .rightClick)

        if wantsRightHold {
            if isStylusTipDown {
                isStylusTipDown = false
                actions.append(.leftMouseUp(at: screenPoint, clickCount: 1))
            }
            if !isStylusRightDown {
                isStylusRightDown = true
                actions.append(.rightMouseDown(at: screenPoint))
            } else {
                actions.append(.rightMouseDragged(to: screenPoint))
            }
            return actions
        } else if isStylusRightDown {
            isStylusRightDown = false
            actions.append(.rightMouseUp(at: screenPoint))
            return actions
        }

        let wantsMiddleHold =
            (barrelActive && config.barrelButtonAction == .middleClick) ||
            (topButtonActive && config.secondaryBarrelButtonAction == .middleClick)

        if wantsMiddleHold {
            if isStylusTipDown {
                isStylusTipDown = false
                actions.append(.leftMouseUp(at: screenPoint, clickCount: 1))
            }
            if !isStylusMiddleDown {
                isStylusMiddleDown = true
                actions.append(.middleMouseDown(at: screenPoint))
            } else {
                actions.append(.middleMouseDragged(to: screenPoint))
            }
            return actions
        } else if isStylusMiddleDown {
            isStylusMiddleDown = false
            actions.append(.middleMouseUp(at: screenPoint))
            return actions
        }

        // 4. Evaluate Pen Tip contact & pressure-sensitive drawing
        let tipTouching = sample.isTipTouching
        let clampedPressure = max(sample.pressure, 0.1)

        if tipTouching && !isStylusTipDown {
            isStylusTipDown = true
            actions.append(.leftMouseDown(at: screenPoint, clickCount: 1))
        } else if tipTouching && isStylusTipDown {
            actions.append(.leftMouseDragged(to: screenPoint, pressure: clampedPressure))
        } else if !tipTouching && isStylusTipDown {
            isStylusTipDown = false
            actions.append(.leftMouseUp(at: screenPoint, clickCount: 1))
        } else if sample.inRange {
            actions.append(.moveCursor(to: screenPoint))
        }

        return actions
    }

    // MARK: - 1-Finger State Machine

    private func handleOneFinger(_ contact: MappedContact, timestamp: TimeInterval) -> [GestureAction] {
        let p = contact.point

        switch state {
        case .idle:
            let nextClickCount: Int
            if timestamp - lastTapTime <= doubleTapMaxInterval,
               hypot(p.x - lastTapPoint.x, p.y - lastTapPoint.y) <= doubleTapMaxDistance {
                nextClickCount = (consecutiveTapCount % 3) + 1
            } else {
                nextClickCount = 1
            }
            state = .oneFingerPending(
                id: contact.id,
                startPoint: p,
                lastPoint: p,
                startTime: timestamp,
                clickCount: nextClickCount
            )
            return [.moveCursor(to: p)]

        case let .oneFingerPending(id, startPoint, _, startTime, clickCount):
            guard contact.id == id else {
                state = .oneFingerPending(id: contact.id, startPoint: p, lastPoint: p, startTime: timestamp, clickCount: 1)
                return [.moveCursor(to: p)]
            }

            let distFromStart = hypot(p.x - startPoint.x, p.y - startPoint.y)
            let elapsed = timestamp - startTime
            let threshold = max(config.dragThreshold, 4.0)

            // Wait past the 55ms multi-finger landing window before committing to a 1-finger drag
            // (unless displacement >= 22pt) so a 2-finger tap or scroll never starts a 1-finger drag.
            if distFromStart >= threshold && (elapsed >= multiFingerGraceInterval || distFromStart >= 22.0) {
                switch config.oneFingerMode {
                case .selectAndDrag:
                    state = .oneFingerDragging(id: id, lastPoint: p, clickCount: clickCount)
                    return [
                        .leftMouseDown(at: startPoint, clickCount: clickCount),
                        .leftMouseDragged(to: p, pressure: 1.0)
                    ]

                case .scrollAndHoldToSelect:
                    if elapsed >= holdToSelectDuration {
                        state = .oneFingerDragging(id: id, lastPoint: p, clickCount: clickCount)
                        return [
                            .leftMouseDown(at: startPoint, clickCount: clickCount),
                            .leftMouseDragged(to: p, pressure: 1.0)
                        ]
                    } else {
                        state = .oneFingerScrolling(id: id, lastPoint: p)
                        let (dx, dy) = scrollDeltas(from: startPoint, to: p)
                        return [
                            .scroll(at: startPoint, deltaX: 0, deltaY: 0, phase: .began),
                            .scroll(at: p, deltaX: dx, deltaY: dy, phase: .changed)
                        ]
                    }
                }
            } else {
                state = .oneFingerPending(
                    id: id,
                    startPoint: startPoint,
                    lastPoint: p,
                    startTime: startTime,
                    clickCount: clickCount
                )
                return []
            }

        case let .oneFingerDragging(id, lastPoint, clickCount):
            guard contact.id == id else { return [] }
            let step = hypot(p.x - lastPoint.x, p.y - lastPoint.y)
            guard step >= 0.5 else { return [] }
            let smoothed = smooth(from: lastPoint, to: p, alpha: 0.75)
            state = .oneFingerDragging(id: id, lastPoint: smoothed, clickCount: clickCount)
            return [.leftMouseDragged(to: smoothed, pressure: 1.0)]

        case let .oneFingerScrolling(id, lastPoint):
            guard contact.id == id else { return [] }
            let step = hypot(p.x - lastPoint.x, p.y - lastPoint.y)
            guard step >= 0.5 else { return [] }
            let (dx, dy) = scrollDeltas(from: lastPoint, to: p)
            state = .oneFingerScrolling(id: id, lastPoint: p)
            return [.scroll(at: p, deltaX: dx, deltaY: dy, phase: .changed)]

        case let .twoFingerPending(startCentroid, lastCentroid, startSpan, lastSpan, startTime):
            // One of the two fingers lifted before a scroll or pinch started -> if within tap tolerances, fire 2-finger right-click!
            let elapsed = timestamp - startTime
            let moved = hypot(lastCentroid.x - startCentroid.x, lastCentroid.y - startCentroid.y)
            let spanDiff = abs(lastSpan - startSpan)
            state = .waitingForLift
            if config.twoFingerRightClick && elapsed <= twoFingerTapMaxDuration && moved <= twoFingerTapSlop && spanDiff <= twoFingerTapMaxSpanChange {
                return [.rightClick(at: startCentroid)]
            }
            return []

        case let .twoFingerScrolling(lastCentroid, _):
            state = .waitingForLift
            return [.scroll(at: lastCentroid, deltaX: 0, deltaY: 0, phase: .ended)]

        case let .twoFingerPinching(lastCentroid, _, _):
            state = .waitingForLift
            return [.magnify(at: lastCentroid, magnification: 0, phase: .ended)]

        case .multiFingerPending, .waitingForLift:
            state = .waitingForLift
            return []
        }
    }

    // MARK: - 2-Finger State Machine (Right-Click Tap vs Smooth Scroll vs Pinch Zoom)

    private func handleTwoFingers(_ c0: MappedContact, _ c1: MappedContact, timestamp: TimeInterval) -> [GestureAction] {
        let p0 = c0.point
        let p1 = c1.point
        let centroid = CGPoint(x: (p0.x + p1.x) * 0.5, y: (p0.y + p1.y) * 0.5)
        let span = hypot(p1.x - p0.x, p1.y - p0.y)

        switch state {
        case .idle, .oneFingerPending:
            state = .twoFingerPending(
                startCentroid: centroid,
                lastCentroid: centroid,
                startSpan: span,
                lastSpan: span,
                startTime: timestamp
            )
            return []

        case let .oneFingerDragging(_, lastPoint, clickCount):
            state = .twoFingerPending(
                startCentroid: centroid,
                lastCentroid: centroid,
                startSpan: span,
                lastSpan: span,
                startTime: timestamp
            )
            return [.leftMouseUp(at: lastPoint, clickCount: clickCount)]

        case let .oneFingerScrolling(_, lastPoint):
            state = .twoFingerPending(
                startCentroid: centroid,
                lastCentroid: centroid,
                startSpan: span,
                lastSpan: span,
                startTime: timestamp
            )
            return [.scroll(at: lastPoint, deltaX: 0, deltaY: 0, phase: .ended)]

        case let .twoFingerPending(startCentroid, lastCentroid, startSpan, lastSpan, startTime):
            let centroidMove = hypot(centroid.x - startCentroid.x, centroid.y - startCentroid.y)
            let spanChange = abs(span - startSpan)
            let elapsed = timestamp - startTime

            // 1. Pinch-to-Zoom: requires purposeful span expansion/contraction exceeding centroid translation
            if config.pinchToZoom && startSpan > 20.0 && spanChange >= pinchStartThreshold && spanChange >= centroidMove * 1.25 {
                let deltaMag = (span - lastSpan) / max(startSpan, 100.0)
                state = .twoFingerPinching(lastCentroid: centroid, startSpan: startSpan, lastSpan: span)
                return [
                    .magnify(at: centroid, magnification: 0, phase: .began),
                    .magnify(at: centroid, magnification: deltaMag, phase: .changed)
                ]
            }

            // 2. Two-Finger Scroll: requires either >= 20pt movement OR (>= 10pt movement after 160ms hold),
            // so a quick 2-finger tap never accidentally starts scrolling due to fingertip roll.
            let shouldStartScroll = centroidMove >= scrollStartThreshold || (elapsed >= 0.16 && centroidMove >= 10.0)
            if config.twoFingerScroll && shouldStartScroll {
                let (dx, dy) = scrollDeltas(from: lastCentroid, to: centroid)
                state = .twoFingerScrolling(lastCentroid: centroid, lastSpan: span)
                return [
                    .scroll(at: startCentroid, deltaX: 0, deltaY: 0, phase: .began),
                    .scroll(at: centroid, deltaX: dx, deltaY: dy, phase: .changed)
                ]
            }

            state = .twoFingerPending(
                startCentroid: startCentroid,
                lastCentroid: centroid,
                startSpan: startSpan,
                lastSpan: span,
                startTime: startTime
            )
            return []

        case let .twoFingerScrolling(lastCentroid, _):
            let step = hypot(centroid.x - lastCentroid.x, centroid.y - lastCentroid.y)
            guard step >= 0.5 else { return [] }
            let (dx, dy) = scrollDeltas(from: lastCentroid, to: centroid)
            state = .twoFingerScrolling(lastCentroid: centroid, lastSpan: span)
            return [.scroll(at: centroid, deltaX: dx, deltaY: dy, phase: .changed)]

        case let .twoFingerPinching(_, startSpan, lastSpan):
            let spanStep = abs(span - lastSpan)
            guard spanStep >= 1.0 else { return [] }
            let deltaMag = (span - lastSpan) / max(startSpan, 100.0)
            state = .twoFingerPinching(lastCentroid: centroid, startSpan: startSpan, lastSpan: span)
            return [.magnify(at: centroid, magnification: deltaMag, phase: .changed)]

        case .multiFingerPending, .waitingForLift:
            return []
        }
    }

    // MARK: - 3 / 4 / 5-Finger State Machine (MacBook Trackpad Shortcuts)

    private func handleMultiFingers(_ contacts: [MappedContact], timestamp: TimeInterval) -> [GestureAction] {
        guard config.threeFingerSwipes else { return [] }

        let centroid = Self.centroid(of: contacts)
        let span = Self.averageRadius(of: contacts, around: centroid)
        var cleanupActions: [GestureAction] = []

        switch state {
        case let .oneFingerDragging(_, lastPoint, clickCount):
            cleanupActions.append(.leftMouseUp(at: lastPoint, clickCount: clickCount))
        case let .oneFingerScrolling(_, lastPoint):
            cleanupActions.append(.scroll(at: lastPoint, deltaX: 0, deltaY: 0, phase: .ended))
        case let .twoFingerScrolling(lastCentroid, _):
            cleanupActions.append(.scroll(at: lastCentroid, deltaX: 0, deltaY: 0, phase: .ended))
        case let .twoFingerPinching(lastCentroid, _, _):
            cleanupActions.append(.magnify(at: lastCentroid, magnification: 0, phase: .ended))
        default:
            break
        }

        switch state {
        case .idle, .oneFingerPending, .oneFingerDragging, .oneFingerScrolling,
             .twoFingerPending, .twoFingerScrolling, .twoFingerPinching:
            state = .multiFingerPending(
                fingerCount: contacts.count,
                startCentroid: centroid,
                lastCentroid: centroid,
                startSpan: span,
                startTime: timestamp
            )
            return cleanupActions

        case let .multiFingerPending(fingerCount, startCentroid, _, startSpan, startTime):
            let dx = centroid.x - startCentroid.x
            let dy = centroid.y - startCentroid.y
            let dist = hypot(dx, dy)

            // 4/5-finger spread/pinch for Show Desktop if >= 4 fingers expand radially without large centroid translation
            if max(fingerCount, contacts.count) >= 4,
               startSpan > 30,
               abs(span - startSpan) > 55,
               abs(span - startSpan) > dist * 1.3 {
                state = .waitingForLift
                return cleanupActions + [.systemGesture(.showDesktop)]
            }

            if dist >= threeFingerSwipeThreshold {
                if abs(dx) > abs(dy) * 1.2 {
                    // Horizontal 3/4-finger swipe -> Move between macOS Desktops / Spaces
                    // Natural trackpad swipe: swiping fingers left (dx < 0) pulls the right Desktop in (.spaceRight).
                    let gesture: SystemTrackpadGesture
                    if config.naturalSpacesSwipe {
                        gesture = (dx < 0) ? .spaceRight : .spaceLeft
                    } else {
                        gesture = (dx < 0) ? .spaceLeft : .spaceRight
                    }
                    state = .waitingForLift
                    return cleanupActions + [.systemGesture(gesture)]
                } else if abs(dy) > abs(dx) * 1.2 {
                    // Vertical 3/4-finger swipe -> Mission Control (swipe up, dy < 0) or App Exposé (swipe down, dy > 0)
                    let gesture: SystemTrackpadGesture = (dy < 0) ? .missionControl : .appExpose
                    state = .waitingForLift
                    return cleanupActions + [.systemGesture(gesture)]
                }
            }

            state = .multiFingerPending(
                fingerCount: max(fingerCount, contacts.count),
                startCentroid: startCentroid,
                lastCentroid: centroid,
                startSpan: startSpan,
                startTime: startTime
            )
            return cleanupActions

        case .waitingForLift:
            return cleanupActions
        }
    }

    // MARK: - Lift Handling

    private func handleAllFingersLifted(timestamp: TimeInterval) -> [GestureAction] {
        defer { state = .idle }

        switch state {
        case .idle, .waitingForLift, .multiFingerPending:
            return []

        case let .oneFingerPending(_, startPoint, lastPoint, startTime, clickCount):
            let elapsed = timestamp - startTime
            let moved = hypot(lastPoint.x - startPoint.x, lastPoint.y - startPoint.y)
            if config.tapToClick && elapsed <= tapMaxDuration && moved <= max(tapSlop, config.dragThreshold * 2.0) {
                lastTapTime = timestamp
                lastTapPoint = startPoint
                consecutiveTapCount = clickCount
                return [.leftClick(at: startPoint, clickCount: clickCount)]
            }
            return []

        case let .oneFingerDragging(_, lastPoint, clickCount):
            return [.leftMouseUp(at: lastPoint, clickCount: clickCount)]

        case let .oneFingerScrolling(_, lastPoint):
            return [.scroll(at: lastPoint, deltaX: 0, deltaY: 0, phase: .ended)]

        case let .twoFingerPending(startCentroid, lastCentroid, startSpan, lastSpan, startTime):
            let elapsed = timestamp - startTime
            let moved = hypot(lastCentroid.x - startCentroid.x, lastCentroid.y - startCentroid.y)
            let spanDiff = abs(lastSpan - startSpan)
            if config.twoFingerRightClick && elapsed <= twoFingerTapMaxDuration && moved <= twoFingerTapSlop && spanDiff <= twoFingerTapMaxSpanChange {
                return [.rightClick(at: startCentroid)]
            }
            return []

        case let .twoFingerScrolling(lastCentroid, _):
            return [.scroll(at: lastCentroid, deltaX: 0, deltaY: 0, phase: .ended)]

        case let .twoFingerPinching(lastCentroid, _, _):
            return [.magnify(at: lastCentroid, magnification: 0, phase: .ended)]
        }
    }

    // MARK: - Math Helpers

    private func scrollDeltas(from p0: CGPoint, to p1: CGPoint) -> (dx: Double, dy: Double) {
        let sign = config.naturalScrolling ? 1.0 : -1.0
        let dx = (p1.x - p0.x) * config.scrollSensitivity * sign
        let dy = (p1.y - p0.y) * config.scrollSensitivity * sign
        return (dx, dy)
    }

    private func smooth(from previous: CGPoint, to current: CGPoint, alpha: Double) -> CGPoint {
        CGPoint(
            x: previous.x + alpha * (current.x - previous.x),
            y: previous.y + alpha * (current.y - previous.y)
        )
    }

    private static func centroid(of contacts: [MappedContact]) -> CGPoint {
        guard !contacts.isEmpty else { return .zero }
        var sumX = 0.0
        var sumY = 0.0
        for c in contacts {
            sumX += c.point.x
            sumY += c.point.y
        }
        let n = Double(contacts.count)
        return CGPoint(x: sumX / n, y: sumY / n)
    }

    private static func averageRadius(of contacts: [MappedContact], around center: CGPoint) -> Double {
        guard !contacts.isEmpty else { return 0 }
        var sum = 0.0
        for c in contacts {
            sum += hypot(c.point.x - center.x, c.point.y - center.y)
        }
        return sum / Double(contacts.count)
    }
}
