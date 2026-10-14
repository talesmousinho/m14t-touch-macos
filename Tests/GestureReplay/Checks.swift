import CoreGraphics
#if SWIFT_PACKAGE
@testable import M14tTouch
#endif

/// Shared scenarios for XCTest and the Command Line Tools-only runner.
func runGestureReplayChecks(_ check: (Bool, String) -> Void) {
    func contact(_ id: Int, _ x: Double, _ y: Double) -> TouchContact {
        TouchContact(id: id, point: CGPoint(x: x, y: y))
    }
    func report(_ contacts: [TouchContact]) -> [UInt8] {
        // Gen 1 descriptor: ID, reserved byte, count, five 7-byte contacts, scan time.
        var bytes = [UInt8](repeating: 0, count: 40)
        bytes[0] = 0x0c
        bytes[2] = UInt8(contacts.count)
        for (slot, contact) in contacts.enumerated() {
            let offset = 3 + slot * 7
            bytes[offset] = 0x05 // Tip Switch + Confidence
            for (index, value) in [contact.id, Int(contact.point.x), Int(contact.point.y)].enumerated() {
                bytes[offset + 1 + index * 2] = UInt8(value & 255)
                bytes[offset + 2 + index * 2] = UInt8((value >> 8) & 255)
            }
        }
        return bytes
    }
    let p = CGPoint(x: 300, y: 1400)
    let first = contact(1, 300, 1400)
    let second = contact(2, 500, 1400)

    // Decode whole reports, never combine partial X/Y values from different fingers.
    let raw = [contact(7, 12300, 6950), contact(258, 5000, 3200)]
    check(M14tReport.decode(report(raw)) == raw, "decode separate contacts and 16-bit IDs")
    check(M14tReport.decode(report([])) == [], "empty report releases fingers")
    check(M14tReport.decode([0x0c, 0]) == nil, "reject truncated report")
    var wrong = report(raw); wrong[0] = 0x20
    check(M14tReport.decode(wrong) == nil, "ignore secondary interface and pen")
    var malformed = report(raw); malformed[2] = 6
    check(M14tReport.decode(malformed) == nil, "reject impossible contact count")
    var mismatch = report(raw); mismatch[2] = 1
    check(M14tReport.decode(mismatch) == nil, "reject incomplete or inconsistent frame")
    check(M14tReport.decode(report([first, first])) == nil, "reject duplicate contact IDs")
    var palm = report([first]); palm[3] = 1
    check(M14tReport.decode(palm) == [], "ignore unconfident palm contact")
    var lifted = report([first]); lifted[3] = 4
    check(M14tReport.decode(lifted) == [], "lift report releases even if count still includes lifted slot")

    var gesture = TouchGestures()
    check(gesture.update([first], at: 0) == [.move(p)], "first touch moves cursor without clicking")
    check(gesture.update([], at: 0.05) == [.down(p), .up(p)], "short single tap clicks once")
    check(gesture.update([], at: 0.06).isEmpty, "release does not repeat click")

    gesture = TouchGestures()
    _ = gesture.update([first], at: 0)
    check(gesture.update([first], at: 0.13) == [.down(p)], "hold starts drag after gesture grace period")
    let moved = contact(1, 320, 1450)
    check(gesture.update([moved], at: 0.14) == [.drag(moved.point)], "one-finger drag uses complete coordinate pair")
    check(gesture.update([], at: 0.15) == [.up(moved.point)], "drag releases at last position")

    gesture = TouchGestures()
    _ = gesture.update([first], at: 0)
    let center = CGPoint(x: 400, y: 1400)
    check(gesture.update([first, second], at: 0.05) == [.move(center)], "second finger cancels pending click")
    check(gesture.update([contact(2, 515, 1430), contact(1, 315, 1430)], at: 0.07)
          == [.scroll(at: center, dx: 15, dy: 30)], "two-finger scroll follows centroid regardless of slot order")
    check(gesture.update([contact(1, 315, 1430)], at: 0.08).isEmpty, "lifting one scrolling finger must not click")
    check(gesture.update([contact(1, 320, 1440)], at: 0.2).isEmpty, "remaining finger stays suppressed")
    check(gesture.update([], at: 0.3).isEmpty, "all fingers lifted resets scrolling")
    _ = gesture.update([first], at: 0.4)
    check(gesture.update([], at: 0.45) == [.down(p), .up(p)], "tap works again after scroll")

    gesture = TouchGestures()
    _ = gesture.update([first], at: 0)
    _ = gesture.update([first], at: 0.13)
    check(gesture.update([first, second], at: 0.2) == [.up(p), .move(center)], "second finger releases existing drag before scrolling")
    check(gesture.cancel().isEmpty, "cancel scroll leaves no mouse button held")

    gesture = TouchGestures()
    _ = gesture.update([first], at: 0)
    _ = gesture.update([first], at: 0.13)
    check(gesture.cancel() == [.up(p)], "disconnect or shutdown releases held mouse button")
    check(gesture.cancel().isEmpty, "cancel is idempotent")

    gesture = TouchGestures()
    _ = gesture.update([first, second], at: 0)
    check(gesture.update([first, contact(3, 900, 1600)], at: 0.1).isEmpty, "contact replacement cannot jump scroll")
    check(gesture.update([first], at: 0.2).isEmpty, "replaced pair stays suppressed until lift")

    gesture = TouchGestures()
    _ = gesture.update([first, second, contact(3, 700, 1400)], at: 0)
    check(gesture.update([first], at: 0.2).isEmpty, "three-finger gesture cannot become accidental click")
    check(gesture.update([], at: 0.3).isEmpty, "three-finger gesture ends without clicks")

    // Existing saved calibration and multi-display mapping remain applicable.
    let mapper = CoordinateMapper(calibration: CalibrationData(xMin: 0, xMax: 12266, yMin: 0, yMax: 6959),
        displayBounds: CGRect(x: 0, y: 1080, width: 1920, height: 1080), invertX: false, invertY: false)
    check(mapper.map(rawX: 6133, rawY: 3479.5) == CGPoint(x: 960, y: 1620), "saved calibration maps M14t center")
    check(mapper.map(rawX: 0, rawY: 0) == CGPoint(x: 0, y: 1080), "saved calibration maps top-left")
    if case .run(let config) = ArgumentParser.parse(["--two-finger-scroll", "--display", "1"]) {
        check(config.twoFingerScroll && config.displayIndex == 1, "CLI enables scrolling on selected display")
    } else { check(false, "CLI parses scroll option") }
    if case .run(let config) = ArgumentParser.parse([]) {
        check(!config.twoFingerScroll, "legacy single-touch mode remains default")
    } else { check(false, "CLI parses default mode") }

    gesture = TouchGestures()
    _ = gesture.update([first, second], at: 0)
    check(gesture.update([first, second], at: 0.02).isEmpty, "stationary pair emits no scroll")
    check(gesture.update([contact(1, 280, 1360), contact(2, 480, 1360)], at: 0.04)
          == [.scroll(at: center, dx: -20, dy: -40)], "reverse scroll preserves direction and magnitude")
    check(gesture.update([], at: 0.05).isEmpty, "two-finger lift emits no click")

    gesture = TouchGestures()
    _ = gesture.update([first], at: 0)
    _ = gesture.update([first], at: 0.13)
    check(gesture.update([first, second, contact(3, 700, 1400)], at: 0.14) == [.up(p)], "third finger safely releases active drag")

    // Reproduce the driver's rejected-report recovery while a gesture is active.
    gesture = TouchGestures()
    _ = gesture.update([first, second], at: 0)
    _ = gesture.interrupt()
    check(gesture.update([first], at: 0.05).isEmpty, "rejected scroll frame suppresses remaining finger")
    check(gesture.update([], at: 0.06).isEmpty, "lifting after rejected frame must not click")
    _ = gesture.update([first], at: 0.1)
    check(gesture.update([], at: 0.15) == [.down(p), .up(p)], "tap recovers after rejected frame and complete lift")

    gesture = TouchGestures()
    _ = gesture.update([first], at: 0)
    _ = gesture.update([first], at: 0.13)
    check(gesture.interrupt() == [.up(p)], "rejected frame releases active drag")
    check(gesture.update([first], at: 0.14).isEmpty, "rejected drag frame suppresses remaining finger")
    check(gesture.update([], at: 0.15).isEmpty, "rejected drag frame cannot produce a release click")

    // Display indices change when another screen becomes main. Identity must not.
    let touchUUID = "11111111-1111-4111-8111-111111111111"
    let otherUUID = "22222222-2222-4222-8222-222222222222"
    let oldTouch = DisplayInfo(index: 1, id: 3, uuid: touchUUID,
        bounds: CGRect(x: 2560, y: 0, width: 1920, height: 1080), isMain: false)
    let other = DisplayInfo(index: 0, id: 2, uuid: otherUUID,
        bounds: CGRect(x: 0, y: 0, width: 2560, height: 1080), isMain: true)
    var target = DisplayTarget(index: 1, uuid: nil, displays: [other, oldTouch])
    check(target.uuid == touchUUID && target.current == oldTouch, "index selection pins display identity")
    let movedDisplay = DisplayInfo(index: 0, id: 3, uuid: touchUUID,
        bounds: CGRect(x: -1600, y: -900, width: 1600, height: 900), isMain: true)
    check(target.refresh([movedDisplay, other]), "move, resize and main-display change refresh target")
    check(target.current == movedDisplay, "reordered displays retain touch screen")
    var movedMapper = mapper
    movedMapper.displayBounds = target.current!.bounds
    check(movedMapper.map(rawX: 6133, rawY: 3479.5) == CGPoint(x: -800, y: -450), "new coordinates include negative origin and new size")
    check(!target.refresh([movedDisplay, other]), "unchanged layout does not interrupt gestures")
    check(target.refresh([other]) && target.current == nil, "missing target pauses without main-display fallback")
    let returned = DisplayInfo(index: 1, id: 99, uuid: touchUUID, bounds: oldTouch.bounds, isMain: false)
    check(target.refresh([other, returned]) && target.current == returned, "reconnect follows UUID despite changed display ID")
    var absent = DisplayTarget(index: 1, uuid: touchUUID, displays: [other])
    check(absent.current == nil && absent.refresh([returned]), "saved UUID can wait for monitor at login")
    check(DisplayTarget(index: 9, uuid: nil, displays: [other]).uuid == nil, "invalid index never falls back to another screen")
    if case .run(let config) = ArgumentParser.parse(["--display-uuid", touchUUID.lowercased()]) {
        check(config.displayUUID == touchUUID, "CLI normalizes stable display UUID")
    } else { check(false, "CLI accepts display UUID") }
    if case .error = ArgumentParser.parse(["--display-uuid", "bad"]) {
        check(true, "CLI rejects malformed display UUID")
    } else { check(false, "CLI rejects malformed display UUID") }
    if case .printDisplayUUID(let config) = ArgumentParser.parse(["--print-display-uuid", "--display", "0"]) {
        check(config.displayIndex == 0, "UUID lookup accepts later display option")
    } else { check(false, "CLI supports installer UUID lookup") }

    gesture = TouchGestures()
    _ = gesture.update([first], at: 0)
    check(gesture.interrupt().isEmpty && !gesture.isPending, "layout change cancels delayed press")
    check(gesture.update([first], at: 1).isEmpty, "timer cannot click stale coordinates after layout change")
    _ = gesture.update([], at: 1.1)
    _ = gesture.update([first, second], at: 2)
    _ = gesture.interrupt()
    check(gesture.update([first, second], at: 2.1).isEmpty, "layout change discards old scroll anchor")
    _ = gesture.update([], at: 2.2)
    let newFirst = contact(1, -900, -450)
    let newSecond = contact(2, -700, -450)
    check(gesture.update([newFirst, newSecond], at: 3) == [.move(CGPoint(x: -800, y: -450))], "new scroll anchors on moved touch display")

    // USB can continue reporting a release while the video connection is absent.
    gesture = TouchGestures()
    _ = gesture.update([first], at: 0)
    _ = gesture.update([first], at: 0.13)
    check(gesture.update([first], at: 0.2, inputEnabled: false) == [.up(p)], "missing display releases active drag")
    check(gesture.update([first, second], at: 0.3, inputEnabled: false).isEmpty, "missing display cannot start scroll")
    check(gesture.update([], at: 0.4, inputEnabled: false).isEmpty, "release while missing emits no click")
    check(gesture.update([newFirst], at: 0.5) == [.move(newFirst.point)], "first touch after reconnect works when fingers lifted while missing")
    check(gesture.update([], at: 0.55) == [.down(newFirst.point), .up(newFirst.point)], "reconnected tap lands in new coordinate space")
    _ = gesture.update([first, second], at: 1, inputEnabled: false)
    check(gesture.update([first, second], at: 1.1).isEmpty, "fingers held through reconnect remain suppressed until lift")

}
