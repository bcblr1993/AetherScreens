import XCTest
@testable import AetherScreensCore

final class AppleFileCopyControlTests: XCTestCase {
    func testStopMatchesIndependentHeaderOnlyWireFixture() throws {
        let message = AppleFileCopyControl.stop.message(sessionID: 0x12345678)
        XCTAssertEqual(try message.encode(), Data([0x22, 0, 0, 0, 0, 8, 0, 1, 0, 5, 0x12, 0x34, 0x56, 0x78]))
        XCTAssertEqual(AppleFileCopyControl.decode(message, expectedSessionID: 0x12345678), .stop)
    }

    func testControlsRemainScopedToVersionSessionAndEmptyBody() {
        for control in [AppleFileCopyControl.pause, .resume, .stop] {
            let message = control.message(sessionID: 42)
            XCTAssertEqual(AppleFileCopyControl.decode(message, expectedSessionID: 42), control)
            XCTAssertNil(AppleFileCopyControl.decode(message, expectedSessionID: 43))
            XCTAssertNil(AppleFileCopyControl.decode(.init(version: 2, command: control.rawValue,
                sessionID: 42, body: Data()), expectedSessionID: 42))
            XCTAssertNil(AppleFileCopyControl.decode(.init(version: 1, command: control.rawValue,
                sessionID: 42, body: Data([0])), expectedSessionID: 42))
        }
        for command: UInt16 in [0, 1, 2, 100, 104, 200, 300, UInt16.max] {
            XCTAssertNil(AppleFileCopyControl.decode(.init(version: 1, command: command,
                sessionID: 42, body: Data()), expectedSessionID: 42))
        }
    }
}
