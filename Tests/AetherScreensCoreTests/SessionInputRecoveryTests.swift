import XCTest
@testable import AetherScreensCore

final class SessionInputRecoveryTests: XCTestCase {
    @MainActor
    func testViewportBoundaryDoesNotPublishRedundantOffsets() {
        let session = SessionViewModel(device: RemoteDevice(name: "Viewport QA", host: "qa.invalid"),
            password: nil, isTemporary: true)
        var published: [CGSize] = []
        let subscription = session.$viewOffset.dropFirst().sink { published.append($0) }
        session.panViewport(dx: 300, dy: -300, limitX: 100, limitY: 80)
        XCTAssertEqual(session.viewOffset, CGSize(width: 100, height: -80))
        for _ in 0..<100 {
            session.panViewport(dx: 10, dy: -10, limitX: 100, limitY: 80)
        }
        XCTAssertEqual(published.count, 1)
        session.panViewport(dx: -20, dy: 20, limitX: 100, limitY: 80)
        XCTAssertEqual(session.viewOffset, CGSize(width: 80, height: -60))
        XCTAssertEqual(published.count, 2)
        session.panViewport(dx: 0, dy: 0, limitX: 30, limitY: 20)
        XCTAssertEqual(session.viewOffset, CGSize(width: 30, height: -20))
        session.panViewport(dx: 0, dy: 0, limitX: 0, limitY: 0)
        XCTAssertEqual(session.viewOffset, .zero)
        session.panViewport(dx: 0, dy: 0, limitX: 100, limitY: 80)
        XCTAssertEqual(session.viewOffset, .zero)
        XCTAssertEqual(published.count, 4)
        subscription.cancel()
        session.endSession()
    }

    @MainActor
    func testDisconnectAndFailureClearLocalInputAndReplaceViewIdentity() {
        for state in [RFBClient.State.disconnected, .failed("Synthetic connection failure")] {
            let session = SessionViewModel(device: RemoteDevice(name: "Recovery QA", host: "qa.invalid"),
                password: nil, isTemporary: true)
            session.cmdState = .locked
            session.optState = .activeOnce
            session.ctrlState = .locked
            session.shiftState = .activeOnce
            session.trackpadEngine.beginDrag(button: [.left, .right])
            let identity = session.inputGeneration
            session.client.onStateChanged?(state)
            let drained = expectation(description: "Session state callback drained")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { drained.fulfill() }
            wait(for: [drained], timeout: 1)
            XCTAssertEqual(session.sessionState, state)
            XCTAssertEqual(session.cmdState, .inactive)
            XCTAssertEqual(session.optState, .inactive)
            XCTAssertEqual(session.ctrlState, .inactive)
            XCTAssertEqual(session.shiftState, .inactive)
            XCTAssertTrue(session.trackpadEngine.activeButtons.isEmpty)
            XCTAssertNotEqual(session.inputGeneration, identity)
            session.endSession()
        }
    }
}
