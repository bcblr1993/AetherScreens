import XCTest
@testable import AetherScreensCore

@MainActor
final class SessionRegistryTests: XCTestCase {
    func testSavedRequestDoesNotReuseAnExplicitIndependentSession() {
        let registry = SessionRegistry()
        let device = RemoteDevice(name: "QA", host: "qa.invalid")
        let independent = SessionViewModel(device: device, password: nil, isTemporary: true)
        independent.isObserveOnly = true
        let separate = registry.register(independent, reuseExisting: false)
        let saved = SessionViewModel(device: device, password: nil, isTemporary: true)
        let normal = registry.register(saved)
        XCTAssertNotEqual(normal, separate)
        XCTAssertTrue(registry.session(for: normal) === saved)
        XCTAssertEqual(registry.register(SessionViewModel(device: device, password: nil, isTemporary: true)), normal)
        XCTAssertEqual(registry.sessions.count, 2)
    }

    func testMobileSelectionPreservesViewportsAndReleasesHiddenInput() {
        let registry = SessionRegistry()
        let first = SessionViewModel(device: RemoteDevice(name: "First", host: "127.0.0.1"), password: nil, isTemporary: true)
        let second = SessionViewModel(device: RemoteDevice(name: "Second", host: "127.0.0.1"), password: nil, isTemporary: true)
        let firstID = registry.register(first), secondID = registry.register(second)
        first.zoomScale = 2.5
        first.viewOffset = CGSize(width: 30, height: 20)
        XCTAssertTrue(registry.activate(firstID) === first)
        first.cycleCmd()
        first.trackpadEngine.beginDrag()
        first.isKeyboardVisible = true
        first.isTextInputBarVisible = true
        let oldInput = first.inputGeneration
        XCTAssertTrue(registry.activate(secondID) === second)
        XCTAssertFalse(first.isForegroundSession)
        XCTAssertTrue(second.isForegroundSession)
        XCTAssertFalse(first.isCmdActive)
        XCTAssertTrue(first.trackpadEngine.activeButtons.isEmpty)
        XCTAssertFalse(first.isKeyboardVisible)
        XCTAssertFalse(first.isTextInputBarVisible)
        XCTAssertNotEqual(first.inputGeneration, oldInput)
        XCTAssertEqual(first.zoomScale, 2.5)
        XCTAssertEqual(first.viewOffset, CGSize(width: 30, height: 20))
        registry.returnToLibrary()
        XCTAssertNil(registry.activeSessionID)
        XCTAssertFalse(second.isForegroundSession)
        XCTAssertTrue(registry.activate(firstID) === first)
        XCTAssertTrue(first.isForegroundSession)
        XCTAssertEqual(first.client.state, .disconnected, "Selection must not reconnect sockets")
        registry.close(secondID)
        XCTAssertTrue(registry.session(for: firstID) === first)
        XCTAssertNil(registry.session(for: secondID))
        XCTAssertEqual(registry.activeSessionID, firstID)
        XCTAssertNil(registry.activate(UUID()))
        XCTAssertEqual(registry.activeSessionID, firstID)
    }

    func testOpeningSavedConnectionAgainPreservesLiveSessionState() {
        let registry = SessionRegistry()
        let device = RemoteDevice(name: "QA", host: "127.0.0.1")
        let original = SessionViewModel(device: device, password: nil, isTemporary: true)
        original.zoomScale = 2.5
        original.isObserveOnly = true
        let id = registry.register(original)
        let replacement = SessionViewModel(device: device, password: nil, isTemporary: true)
        XCTAssertEqual(registry.register(replacement), id)
        XCTAssertTrue(registry.session(for: id) === original)
        XCTAssertEqual(registry.sessions.count, 1)
        XCTAssertEqual(original.zoomScale, 2.5)
        XCTAssertTrue(original.isObserveOnly)
        XCTAssertEqual(original.client.state, .disconnected, "Selecting sessions must not initiate network connections")
    }

    func testExplicitNewWindowKeepsIndependentInputAndViewState() {
        let registry = SessionRegistry()
        let device = RemoteDevice(name: "QA", host: "127.0.0.1")
        let first = SessionViewModel(device: device, password: nil, isTemporary: true)
        let second = SessionViewModel(device: device, password: nil, isTemporary: true)
        let firstID = registry.register(first)
        let secondID = registry.register(second, reuseExisting: false)
        XCTAssertNotEqual(firstID, secondID)
        XCTAssertEqual(registry.sessions.map(\.title), ["QA · 1", "QA · 2"])
        first.zoomScale = 3
        first.isObserveOnly = true
        first.textInputBuffer = "first window"
        XCTAssertEqual(second.zoomScale, 1)
        XCTAssertFalse(second.isObserveOnly)
        XCTAssertTrue(second.textInputBuffer.isEmpty)
        XCTAssertTrue(registry.remove(firstID) === first)
        XCTAssertNil(registry.session(for: firstID))
        XCTAssertTrue(registry.session(for: secondID) === second)
        XCTAssertEqual(registry.sessions.count, 1)
        XCTAssertNil(registry.remove(firstID))
        let third = SessionViewModel(device: device, password: nil, isTemporary: true)
        registry.register(third, reuseExisting: false)
        XCTAssertEqual(registry.sessions.map(\.title), ["QA · 2", "QA · 3"], "Closing a window must not renumber live sessions")
    }

    func testTemporaryConnectionsAndDifferentDevicesAreDistinct() {
        let registry = SessionRegistry()
        let first = SessionViewModel(device: RemoteDevice(name: "Temporary", host: "127.0.0.1"), password: nil, isTemporary: true)
        let second = SessionViewModel(device: RemoteDevice(name: "Temporary", host: "127.0.0.1"), password: nil, isTemporary: true)
        XCTAssertNotEqual(registry.register(first), registry.register(second))
        XCTAssertEqual(registry.sessions.count, 2)
        XCTAssertTrue(registry.sessions.allSatisfy { $0.viewModel.isTemporary })
    }
}
