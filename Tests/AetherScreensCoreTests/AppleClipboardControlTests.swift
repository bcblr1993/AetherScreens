import XCTest
@testable import AetherScreensCore

final class AppleClipboardControlTests: XCTestCase {
    func testFetchAndPromiseMessagesHaveExactEightByteFraming() {
        XCTAssertEqual(AppleClipboardControl.request(), Data([11, 0, 0, 0, 0, 0, 0, 0]))
        XCTAssertEqual(AppleClipboardControl.request(promiseOnly: true), Data([11, 1, 0, 0, 0, 0, 0, 0]))
    }
    func testMonitoringHasSymmetricStartAndStopSelectors() {
        XCTAssertEqual(AppleClipboardControl.monitoring(true), Data([21, 0, 0, 1, 0, 0, 0, 0]))
        XCTAssertEqual(AppleClipboardControl.monitoring(false), Data([21, 0, 0, 2, 0, 0, 0, 0]))
    }
}
