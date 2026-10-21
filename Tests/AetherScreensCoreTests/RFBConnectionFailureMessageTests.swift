import XCTest
@testable import AetherScreensCore

final class RFBConnectionFailureMessageTests: XCTestCase {
    func testCloseBeforeAnyHandshakeByteExplainsLikelyCause() {
        for state: RFBClient.State in [.connecting, .negotiatingVersion] {
            XCTAssertEqual(
                RFBClient.closedConnectionMessage(received: 0, expected: 12, state: state),
                RFBClient.closedBeforeHandshakeMessage
            )
        }
    }

    func testLaterCloseKeepsByteCountsForDiagnosis() {
        XCTAssertEqual(
            RFBClient.closedConnectionMessage(received: 0, expected: 4, state: .authenticating),
            "Remote host closed connection (received 0/4 bytes)"
        )
        XCTAssertEqual(
            RFBClient.closedConnectionMessage(received: 5, expected: 12, state: .negotiatingVersion),
            "Remote host closed connection (received 5/12 bytes)"
        )
    }

    @MainActor
    func testHandshakeCloseMessageIsLocalized() {
        let previous = AppLocalization.language
        defer { AppLocalization.select(previous) }
        AppLocalization.select(.simplifiedChinese)
        XCTAssertTrue(AppLocalization.message(RFBClient.closedBeforeHandshakeMessage).contains("屏幕共享"))
    }
}
