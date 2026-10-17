import XCTest
import CoreGraphics
@testable import M14tTouchCore

final class CoordinateMapperTests: XCTestCase {

    private func makeMapper(
        invertX: Bool = false,
        invertY: Bool = false,
        rotationDegrees: Int = 0
    ) -> CoordinateMapper {
        CoordinateMapper(
            calibration: CalibrationData(xMin: 0, xMax: 12000, yMin: 0, yMax: 7000),
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            invertX: invertX,
            invertY: invertY,
            rotationDegrees: rotationDegrees
        )
    }

    func testTopLeftMapsToOrigin() {
        let p = makeMapper().map(rawX: 0, rawY: 0)
        XCTAssertEqual(p.x, 0, accuracy: 0.5)
        XCTAssertEqual(p.y, 0, accuracy: 0.5)
    }

    func testBottomRightMapsToFarCorner() {
        let p = makeMapper().map(rawX: 12000, rawY: 7000)
        XCTAssertEqual(p.x, 1919.5, accuracy: 0.6)
        XCTAssertEqual(p.y, 1079.5, accuracy: 0.6)
    }

    func testCenterMapsToCenter() {
        let p = makeMapper().map(rawX: 6000, rawY: 3500)
        XCTAssertEqual(p.x, 960, accuracy: 0.5)
        XCTAssertEqual(p.y, 540, accuracy: 0.5)
    }

    func testOutOfRangeIsClamped() {
        let p = makeMapper().map(rawX: 99999, rawY: -50)
        XCTAssertEqual(p.x, 1919.5, accuracy: 0.6)
        XCTAssertEqual(p.y, 0, accuracy: 0.5)
    }

    func testInvertXMirrorsHorizontally() {
        let p = makeMapper(invertX: true).map(rawX: 0, rawY: 3500)
        XCTAssertEqual(p.x, 1919.5, accuracy: 0.6)
    }

    func testInvertYMirrorsVertically() {
        let p = makeMapper(invertY: true).map(rawX: 6000, rawY: 0)
        XCTAssertEqual(p.y, 1079.5, accuracy: 0.6)
    }

    func testDisplayOffsetWithNegativeYIsApplied() {
        var mapper = makeMapper()
        mapper.displayBounds = CGRect(x: 1470, y: -124, width: 1920, height: 1080)
        let p = mapper.map(rawX: 0, rawY: 0)
        XCTAssertEqual(p.x, 1470, accuracy: 0.5)
        XCTAssertEqual(p.y, -124, accuracy: 0.5)
    }

    func testDisplayRotation90Degrees() {
        let mapper = makeMapper(rotationDegrees: 90)
        let p = mapper.mapNormalized(u: 0.25, v: 0.0)
        // At 90°, (u=0.25, v=0.0) -> (rx = 1.0 - 0.0 = 1.0, ry = 0.25)
        XCTAssertEqual(p.x, 1919.5, accuracy: 0.6)
        XCTAssertEqual(p.y, 270.0, accuracy: 0.5)
    }

    func testDegenerateCalibrationDoesNotCrash() {
        var mapper = makeMapper()
        mapper.calibration = CalibrationData(xMin: 5, xMax: 5, yMin: 0, yMax: 0)
        let p = mapper.map(rawX: 5, rawY: 0)
        XCTAssertEqual(p.x, mapper.displayBounds.minX, accuracy: 0.5)
    }
}

final class HIDReportParserTests: XCTestCase {

    private func buildReport0x0C(
        contactCount: UInt8,
        slots: [(tip: Bool, id: UInt16, x: UInt16, y: UInt16)],
        scanTime: UInt16 = 100
    ) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 40)
        bytes[0] = 0x0C
        bytes[1] = 0x00
        bytes[2] = contactCount
        for i in 0..<min(slots.count, 5) {
            let base = 3 + i * 7
            let s = slots[i]
            bytes[base] = s.tip ? 0x05 : 0x00 // TipSwitch + Confidence
            bytes[base + 1] = UInt8(s.id & 0xFF)
            bytes[base + 2] = UInt8((s.id >> 8) & 0xFF)
            bytes[base + 3] = UInt8(s.x & 0xFF)
            bytes[base + 4] = UInt8((s.x >> 8) & 0xFF)
            bytes[base + 5] = UInt8(s.y & 0xFF)
            bytes[base + 6] = UInt8((s.y >> 8) & 0xFF)
        }
        bytes[38] = UInt8(scanTime & 0xFF)
        bytes[39] = UInt8((scanTime >> 8) & 0xFF)
        return bytes
    }

    func testSingleFingerReportIgnoresEmptyTrailingSlots() {
        var parser = HIDReportParser()
        let packet = buildReport0x0C(
            contactCount: 1,
            slots: [
                (tip: true, id: 1, x: 6186, y: 3480),
                (tip: false, id: 0, x: 0, y: 0),
                (tip: false, id: 0, x: 0, y: 0),
                (tip: false, id: 0, x: 0, y: 0),
                (tip: false, id: 0, x: 0, y: 0)
            ]
        )

        guard case let .touchFrame(frame) = parser.parse(bytes: packet, timestamp: 1.0) else {
            return XCTFail("Expected .touchFrame")
        }

        XCTAssertEqual(frame.activeContacts.count, 1)
        XCTAssertEqual(frame.activeContacts[0].id, 1)
        XCTAssertEqual(frame.activeContacts[0].normalizedX, 0.5, accuracy: 0.001)
        XCTAssertEqual(frame.activeContacts[0].normalizedY, 0.5, accuracy: 0.001)
    }

    func testThreeFingerMultiTouchPacket() {
        var parser = HIDReportParser()
        let packet = buildReport0x0C(
            contactCount: 3,
            slots: [
                (tip: true, id: 1, x: 2000, y: 3000),
                (tip: true, id: 2, x: 4000, y: 3000),
                (tip: true, id: 3, x: 6000, y: 3000)
            ]
        )

        guard case let .touchFrame(frame) = parser.parse(bytes: packet, timestamp: 2.0) else {
            return XCTFail("Expected .touchFrame")
        }

        XCTAssertEqual(frame.activeContacts.count, 3)
        XCTAssertEqual(frame.activeContacts.map(\.id), [1, 2, 3])
    }

    func testMouseFallbackReport0x01IsIgnored() {
        var parser = HIDReportParser()
        let mousePacket: [UInt8] = [0x01, 0x01, 0xFF, 0x7F, 0xFF, 0x7F]
        XCTAssertEqual(parser.parse(bytes: mousePacket, timestamp: 1.0), .ignored)
    }

    func testStylusReport0x06Decoding() {
        var parser = HIDReportParser()
        // ReportID 0x06, flags = TipSwitch (0x01) | InRange (0x20), X = 15465, Y = 8700, Pressure = 2048
        let packet: [UInt8] = [
            0x06,
            0x21,
            UInt8(15465 & 0xFF), UInt8((15465 >> 8) & 0xFF),
            UInt8(8700 & 0xFF), UInt8((8700 >> 8) & 0xFF),
            UInt8(2048 & 0xFF), UInt8((2048 >> 8) & 0xFF)
        ]

        guard case let .stylus(sample) = parser.parse(bytes: packet, timestamp: 3.0) else {
            return XCTFail("Expected .stylus")
        }

        XCTAssertTrue(sample.tipSwitch)
        XCTAssertTrue(sample.inRange)
        XCTAssertEqual(sample.normalizedX, 0.5, accuracy: 0.01)
        XCTAssertEqual(sample.normalizedY, 0.5, accuracy: 0.01)
        XCTAssertEqual(sample.pressure, 2048.0 / 4095.0, accuracy: 0.01)
    }
}

final class GestureEngineTests: XCTestCase {

    func testSingleTapAndDoubleTapWordSelection() {
        let engine = GestureEngine()
        let pt = CGPoint(x: 500, y: 400)

        // First tap
        let down1 = engine.processFrame(contacts: [MappedContact(id: 1, point: pt)], timestamp: 1.00)
        XCTAssertEqual(down1, [.moveCursor(to: pt)])
        let up1 = engine.processFrame(contacts: [], timestamp: 1.08)
        XCTAssertEqual(up1, [.leftClick(at: pt, clickCount: 1)])

        // Second rapid tap at same spot -> double-click (selects word)
        _ = engine.processFrame(contacts: [MappedContact(id: 1, point: pt)], timestamp: 1.20)
        let up2 = engine.processFrame(contacts: [], timestamp: 1.28)
        XCTAssertEqual(up2, [.leftClick(at: pt, clickCount: 2)])

        // Third rapid tap at same spot -> triple-click (selects line/paragraph)
        _ = engine.processFrame(contacts: [MappedContact(id: 1, point: pt)], timestamp: 1.40)
        let up3 = engine.processFrame(contacts: [], timestamp: 1.48)
        XCTAssertEqual(up3, [.leftClick(at: pt, clickCount: 3)])
    }

    func testOneFingerDragTextSelection() {
        let engine = GestureEngine(config: TouchConfig(oneFingerMode: .selectAndDrag))
        let start = CGPoint(x: 200, y: 300)
        let mid = CGPoint(x: 240, y: 300)
        let end = CGPoint(x: 300, y: 300)

        _ = engine.processFrame(contacts: [MappedContact(id: 1, point: start)], timestamp: 1.00)
        let drag1 = engine.processFrame(contacts: [MappedContact(id: 1, point: mid)], timestamp: 1.04)
        XCTAssertEqual(drag1, [
            .leftMouseDown(at: start, clickCount: 1),
            .leftMouseDragged(to: mid, pressure: 1.0)
        ])

        let drag2 = engine.processFrame(contacts: [MappedContact(id: 1, point: end)], timestamp: 1.08)
        XCTAssertEqual(drag2.count, 1)
        if case .leftMouseDragged = drag2[0] {} else { XCTFail("Expected .leftMouseDragged") }

        let lift = engine.processFrame(contacts: [], timestamp: 1.12)
        if case .leftMouseUp(_, let clickCount) = lift.first {
            XCTAssertEqual(clickCount, 1)
        } else {
            XCTFail("Expected .leftMouseUp")
        }
    }

    func testLongPressEmitsRightClick() {
        let engine = GestureEngine(config: TouchConfig(longPressRightClick: true, longPressDuration: 0.45))
        let pt = CGPoint(x: 600, y: 500)

        _ = engine.processFrame(contacts: [MappedContact(id: 1, point: pt)], timestamp: 10.0)
        let actions = engine.checkTimeouts(now: 10.50)
        XCTAssertEqual(actions, [.rightClick(at: pt)])

        // Lifting after long-press should not emit a left-click
        let lift = engine.processFrame(contacts: [], timestamp: 10.60)
        XCTAssertTrue(lift.isEmpty)
    }

    func testTwoFingerTapEmitsRightClick() {
        let engine = GestureEngine()
        let c1 = MappedContact(id: 1, point: CGPoint(x: 400, y: 400))
        let c2 = MappedContact(id: 2, point: CGPoint(x: 460, y: 400))

        _ = engine.processFrame(contacts: [c1, c2], timestamp: 5.00)
        let lift = engine.processFrame(contacts: [], timestamp: 5.10)
        XCTAssertEqual(lift, [.rightClick(at: CGPoint(x: 430, y: 400))])
    }

    func testTwoFingerTapWithFingertipRollAndAsyncLiftDoesNotConflictWithScroll() {
        let engine = GestureEngine()
        // Finger 1 lands first
        let f1 = engine.processFrame(
            contacts: [MappedContact(id: 1, point: CGPoint(x: 400, y: 400))],
            timestamp: 5.00
        )
        XCTAssertEqual(f1, [.moveCursor(to: CGPoint(x: 400, y: 400))])

        // Finger 2 lands 20ms later
        let f2 = engine.processFrame(
            contacts: [
                MappedContact(id: 1, point: CGPoint(x: 402, y: 402)),
                MappedContact(id: 2, point: CGPoint(x: 462, y: 402))
            ],
            timestamp: 5.02
        )
        XCTAssertTrue(f2.isEmpty)

        // Slight fingertip roll (10pt < 15pt scroll threshold) during tap
        let roll = engine.processFrame(
            contacts: [
                MappedContact(id: 1, point: CGPoint(x: 402, y: 412)),
                MappedContact(id: 2, point: CGPoint(x: 462, y: 412))
            ],
            timestamp: 5.08
        )
        XCTAssertTrue(roll.isEmpty, "Slight 2-finger tap roll must not start scrolling")

        // Finger 2 lifts first -> triggers rightClick at initial 2-finger centroid
        let liftOne = engine.processFrame(
            contacts: [MappedContact(id: 1, point: CGPoint(x: 402, y: 412))],
            timestamp: 5.11
        )
        XCTAssertEqual(liftOne, [.rightClick(at: CGPoint(x: 432, y: 402))])

        // Finger 1 lifts 15ms later -> no extra click
        let liftAll = engine.processFrame(contacts: [], timestamp: 5.125)
        XCTAssertTrue(liftAll.isEmpty)
    }

    func testTwoFingerPanEmitsSmoothScroll() {
        let engine = GestureEngine()
        _ = engine.processFrame(
            contacts: [
                MappedContact(id: 1, point: CGPoint(x: 400, y: 400)),
                MappedContact(id: 2, point: CGPoint(x: 460, y: 400))
            ],
            timestamp: 1.00
        )

        let move = engine.processFrame(
            contacts: [
                MappedContact(id: 1, point: CGPoint(x: 400, y: 430)),
                MappedContact(id: 2, point: CGPoint(x: 460, y: 430))
            ],
            timestamp: 1.04
        )
        XCTAssertEqual(move.count, 2)
        if case .scroll(_, _, _, let phase0) = move[0] {
            XCTAssertEqual(phase0, .began)
        } else {
            XCTFail("Expected scroll .began")
        }
        if case .scroll(_, _, let dy, let phase1) = move[1] {
            XCTAssertEqual(phase1, .changed)
            XCTAssertGreaterThan(dy, 0)
        } else {
            XCTFail("Expected scroll .changed")
        }
    }

    func testTwoFingerSpreadEmitsPinchZoomMagnify() {
        let engine = GestureEngine()
        // Initial span = 100pt, centroid = (500, 500)
        _ = engine.processFrame(
            contacts: [
                MappedContact(id: 1, point: CGPoint(x: 450, y: 500)),
                MappedContact(id: 2, point: CGPoint(x: 550, y: 500))
            ],
            timestamp: 2.00
        )

        // Spread fingers to span = 160pt around same centroid (500, 500)
        let spread = engine.processFrame(
            contacts: [
                MappedContact(id: 1, point: CGPoint(x: 420, y: 500)),
                MappedContact(id: 2, point: CGPoint(x: 580, y: 500))
            ],
            timestamp: 2.05
        )
        XCTAssertEqual(spread.count, 2)
        if case .magnify(_, let mag, let phase) = spread[1] {
            XCTAssertEqual(phase, .changed)
            XCTAssertGreaterThan(mag, 0.5)
        } else {
            XCTFail("Expected .magnify")
        }
    }

    func testThreeFingerHorizontalSwipeSwitchesMacOSDesktops() {
        let engine = GestureEngine(config: TouchConfig(naturalSpacesSwipe: true))
        _ = engine.processFrame(
            contacts: [
                MappedContact(id: 1, point: CGPoint(x: 600, y: 500)),
                MappedContact(id: 2, point: CGPoint(x: 650, y: 500)),
                MappedContact(id: 3, point: CGPoint(x: 700, y: 500))
            ],
            timestamp: 3.00
        )

        // Swipe 3 fingers left by 80pt -> moves to Desktop on the right (.spaceRight)
        let swipeLeft = engine.processFrame(
            contacts: [
                MappedContact(id: 1, point: CGPoint(x: 520, y: 500)),
                MappedContact(id: 2, point: CGPoint(x: 570, y: 500)),
                MappedContact(id: 3, point: CGPoint(x: 620, y: 500))
            ],
            timestamp: 3.06
        )
        XCTAssertEqual(swipeLeft, [.systemGesture(.spaceRight)])
    }

    func testThreeFingerVerticalSwipesTriggerMissionControlAndAppExpose() {
        let engine = GestureEngine()
        _ = engine.processFrame(
            contacts: [
                MappedContact(id: 1, point: CGPoint(x: 600, y: 500)),
                MappedContact(id: 2, point: CGPoint(x: 650, y: 500)),
                MappedContact(id: 3, point: CGPoint(x: 700, y: 500))
            ],
            timestamp: 4.00
        )

        // Swipe 3 fingers UP (y decreases by 80pt) -> Mission Control
        let swipeUp = engine.processFrame(
            contacts: [
                MappedContact(id: 1, point: CGPoint(x: 600, y: 420)),
                MappedContact(id: 2, point: CGPoint(x: 650, y: 420)),
                MappedContact(id: 3, point: CGPoint(x: 700, y: 420))
            ],
            timestamp: 4.05
        )
        XCTAssertEqual(swipeUp, [.systemGesture(.missionControl)])
    }

    func testSmartPencilHoverPressureTiltAndBothBarrelButtons() {
        let engine = GestureEngine(config: TouchConfig(
            barrelButtonAction: .rightClick,
            secondaryBarrelButtonAction: .eraser,
            palmRejectionWhileStylusInRange: true
        ))
        let pt1 = CGPoint(x: 300, y: 400)
        let pt2 = CGPoint(x: 350, y: 420)

        // 1. Hover in range -> emits tabletProximity(.pen) + stylusHover
        let hover = engine.processStylus(
            sample: StylusSample(
                tipSwitch: false,
                barrelSwitch: false,
                secondaryBarrelSwitch: false,
                eraser: false,
                invert: false,
                inRange: true,
                rawX: 10000,
                rawY: 5000,
                pressure: 0,
                tiltX: 0.25,
                tiltY: -0.5,
                timestamp: 1.0
            ),
            screenPoint: pt1
        )
        XCTAssertEqual(hover, [
            .moveCursor(to: pt1)
        ])

        // 2. Finger touch is processed smoothly
        let fingerTouch = engine.processFrame(
            contacts: [MappedContact(id: 1, point: CGPoint(x: 800, y: 800))],
            timestamp: 1.02
        )
        XCTAssertFalse(fingerTouch.isEmpty, "Finger touch is not blocked")

        // 3. Pen tip touches with 75% pressure -> leftMouseDown
        let tipDown = engine.processStylus(
            sample: StylusSample(
                tipSwitch: true,
                barrelSwitch: false,
                secondaryBarrelSwitch: false,
                eraser: false,
                invert: false,
                inRange: true,
                rawX: 10000,
                rawY: 5000,
                pressure: 0.75,
                tiltX: 0.25,
                tiltY: -0.5,
                timestamp: 1.05
            ),
            screenPoint: pt1
        )
        XCTAssertEqual(tipDown, [
            .leftMouseDown(at: pt1, clickCount: 1)
        ])

        // 4. Pen tip lifts -> leftMouseUp
        let tipUp = engine.processStylus(
            sample: StylusSample(
                tipSwitch: false,
                barrelSwitch: false,
                secondaryBarrelSwitch: false,
                eraser: false,
                invert: false,
                inRange: true,
                rawX: 10000,
                rawY: 5000,
                pressure: 0,
                timestamp: 1.10
            ),
            screenPoint: pt1
        )
        XCTAssertEqual(tipUp, [.leftMouseUp(at: pt1, clickCount: 1)])

        // 5. Bottom barrel button pressed -> rightMouseDown, released -> rightMouseUp
        let barrelDown = engine.processStylus(
            sample: StylusSample(
                tipSwitch: false,
                barrelSwitch: true,
                secondaryBarrelSwitch: false,
                eraser: false,
                invert: false,
                inRange: true,
                rawX: 10000,
                rawY: 5000,
                pressure: 0,
                timestamp: 1.15
            ),
            screenPoint: pt1
        )
        XCTAssertEqual(barrelDown, [.rightMouseDown(at: pt1)])

        let barrelUp = engine.processStylus(
            sample: StylusSample(
                tipSwitch: false,
                barrelSwitch: false,
                secondaryBarrelSwitch: false,
                eraser: false,
                invert: false,
                inRange: true,
                rawX: 10000,
                rawY: 5000,
                pressure: 0,
                timestamp: 1.20
            ),
            screenPoint: pt1
        )
        XCTAssertEqual(barrelUp, [.rightMouseUp(at: pt1)])

        // 6. Top barrel button held + tip touches (Wacom sets eraser=true, tipSwitch=false) -> draws
        let eraserDown = engine.processStylus(
            sample: StylusSample(
                tipSwitch: false,
                barrelSwitch: false,
                secondaryBarrelSwitch: true,
                eraser: true,
                invert: true,
                inRange: true,
                rawX: 12000,
                rawY: 6000,
                pressure: 0.9,
                timestamp: 1.25
            ),
            screenPoint: pt2
        )
        XCTAssertEqual(eraserDown, [
            .leftMouseDown(at: pt2, clickCount: 1)
        ])
    }
}

final class ArgumentParserTests: XCTestCase {

    func testDefaultsWhenEmpty() {
        guard case .run(let config) = ArgumentParser.parse([]) else {
            return XCTFail("expected .run")
        }
        XCTAssertEqual(config.displayIndex, 1)
        XCTAssertTrue(config.autoDetectM14tDisplay)
        XCTAssertEqual(config.displayResolutionPreset, .systemDefault)
        XCTAssertEqual(config.barrelButtonAction, .rightClick)
        XCTAssertEqual(config.secondaryBarrelButtonAction, .eraser)
        XCTAssertTrue(config.palmRejectionWhileStylusInRange)
        XCTAssertFalse(config.autoCalibrate)
        XCTAssertTrue(config.promptForAccessibility)
    }

    func testDisplayIndexAndModeParsed() {
        guard case .run(let config) = ArgumentParser.parse(["--display", "2", "--mode", "scroll"]) else {
            return XCTFail("expected .run")
        }
        XCTAssertEqual(config.displayIndex, 2)
        XCTAssertEqual(config.oneFingerMode, .scrollAndHoldToSelect)
    }

    func testResolutionAndSmartPencilButtonsParsed() {
        let args = [
            "--resolution", "1024x576-hidpi",
            "--barrel-button", "middle",
            "--top-button", "undo",
            "--no-palm-rejection"
        ]
        guard case .run(let config) = ArgumentParser.parse(args) else {
            return XCTFail("expected .run")
        }
        XCTAssertEqual(config.displayResolutionPreset, .hidpi1024x576)
        XCTAssertEqual(config.barrelButtonAction, .middleClick)
        XCTAssertEqual(config.secondaryBarrelButtonAction, .undo)
        XCTAssertFalse(config.palmRejectionWhileStylusInRange)
    }

    func testSetResolutionAndListModesCommands() {
        XCTAssertEqual(
            ArgumentParser.parse(["--set-resolution", "960x540-hidpi"]),
            .setResolution(.hidpi960x540)
        )
        XCTAssertEqual(
            ArgumentParser.parse(["--list-modes"]),
            .listModes
        )
        XCTAssertEqual(
            ArgumentParser.parse(["--check-permissions"]),
            .checkPermissions
        )
        XCTAssertEqual(
            ArgumentParser.parse(["--request-permissions"]),
            .requestPermissions
        )
    }

    func testManualCalibrationFlags() {
        let args = ["--x-min", "1", "--x-max", "12371", "--y-min", "1", "--y-max", "6959"]
        guard case .run(let config) = ArgumentParser.parse(args) else {
            return XCTFail("expected .run")
        }
        XCTAssertEqual(config.manualXMax, 12371)
        XCTAssertTrue(config.hasManualCalibration)
    }

    func testNoAccessibilityPromptParsed() {
        guard case .run(let config) = ArgumentParser.parse(["--no-accessibility-prompt"]) else {
            return XCTFail("expected .run")
        }
        XCTAssertFalse(config.promptForAccessibility)
    }

    func testAutoReturnCursorFlagsParsed() {
        guard case .run(let configEnabled) = ArgumentParser.parse(["--auto-return-cursor"]) else {
            return XCTFail("expected .run")
        }
        XCTAssertTrue(configEnabled.returnCursorToMainDisplay)

        guard case .run(let configDisabled) = ArgumentParser.parse(["--no-auto-return-cursor"]) else {
            return XCTFail("expected .run")
        }
        XCTAssertFalse(configDisabled.returnCursorToMainDisplay)
    }

    func testHelpRecognized() {
        guard case .help = ArgumentParser.parse(["--help"]) else {
            return XCTFail("expected .help")
        }
    }

    func testUnknownOptionIsError() {
        guard case .error = ArgumentParser.parse(["--nope"]) else {
            return XCTFail("expected .error")
        }
    }

    func testMissingDisplayValueIsError() {
        guard case .error = ArgumentParser.parse(["--display"]) else {
            return XCTFail("expected .error")
        }
    }
}

final class PreferencesStoreTests: XCTestCase {

    func testPreferencesRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("config.json")
        let preferences = AppPreferences(
            displayIndex: 2,
            displayResolutionPreset: .hidpi1024x576,
            invertX: true,
            invertY: true,
            debugMode: true,
            dragThreshold: 3.5,
            runAtLogin: true,
            returnCursorToMainDisplay: true,
            oneFingerMode: .scrollAndHoldToSelect,
            barrelButtonAction: .rightClick,
            secondaryBarrelButtonAction: .undo,
            palmRejectionWhileStylusInRange: true,
            manualXMin: 1,
            manualXMax: 12371,
            manualYMin: 1,
            manualYMax: 6959
        )

        try PreferencesStore.save(preferences, to: url)

        XCTAssertEqual(PreferencesStore.load(from: url), preferences)
        XCTAssertTrue(PreferencesStore.reset(at: url))
        XCTAssertNil(PreferencesStore.load(from: url))
    }
}

final class ObservedRangeTests: XCTestCase {

    func testLearnsZeroValuedEdges() {
        var observed = ObservedRange()

        XCTAssertTrue(observed.update(x: 0, y: 0))
        XCTAssertNil(observed.snapshot())
        XCTAssertTrue(observed.update(x: 12000, y: 7000))

        XCTAssertEqual(
            observed.snapshot(),
            CalibrationData(xMin: 0, xMax: 12000, yMin: 0, yMax: 7000)
        )
    }
}

final class CursorAutoReturnTests: XCTestCase {

    func testSyntheticEventUserDataConstant() {
        XCTAssertEqual(MouseEmitter.syntheticEventUserData, 0x4D313454)
    }

    func testTouchConfigDefaultIsFalse() {
        let config = TouchConfig()
        XCTAssertFalse(config.returnCursorToMainDisplay)
    }

    func testAppPreferencesDefaultAndCustomValues() {
        let defaultPrefs = AppPreferences()
        XCTAssertFalse(defaultPrefs.returnCursorToMainDisplay)
        XCTAssertFalse(defaultPrefs.touchConfig.returnCursorToMainDisplay)

        let customPrefs = AppPreferences(returnCursorToMainDisplay: true)
        XCTAssertTrue(customPrefs.returnCursorToMainDisplay)
        XCTAssertTrue(customPrefs.touchConfig.returnCursorToMainDisplay)

        let converted = AppPreferences(touchConfig: customPrefs.touchConfig)
        XCTAssertTrue(converted.returnCursorToMainDisplay)
    }
}
