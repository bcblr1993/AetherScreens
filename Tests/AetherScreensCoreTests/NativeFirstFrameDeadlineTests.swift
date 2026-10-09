import XCTest
@testable import AetherScreensCore

final class NativeFirstFrameDeadlineTests: XCTestCase {
    func testNoProgressAndMidTransferStallsExpire() {
        var deadline = NativeFirstFrameDeadline(now: 100)
        XCTAssertEqual(deadline.remaining(now: 119), 1)
        XCTAssertEqual(deadline.remaining(now: 120), 0)
        deadline.recordPayloadProgress(now: 115)
        XCTAssertEqual(deadline.remaining(now: 120), 15)
        XCTAssertEqual(deadline.remaining(now: 135), 0)
    }
    func testContinuousProgressCannotExtendHardDeadline() {
        var deadline = NativeFirstFrameDeadline(now: 100)
        for now in [110.0, 125, 140, 155] { deadline.recordPayloadProgress(now: now) }
        XCTAssertEqual(deadline.remaining(now: 159), 1)
        XCTAssertEqual(deadline.remaining(now: 160), 0)
        deadline.recordPayloadProgress(now: 170)
        XCTAssertEqual(deadline.remaining(now: 170), 0)
    }
}
