import XCTest

final class GestureReplayTests: XCTestCase {
    func testReportDecodingAndGestureTransitions() {
        runGestureReplayChecks { condition, message in
            XCTAssertTrue(condition, message)
        }
    }
}
