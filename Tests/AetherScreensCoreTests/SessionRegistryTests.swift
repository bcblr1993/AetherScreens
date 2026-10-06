import XCTest
@testable import AetherScreensCore

@MainActor
final class SessionRegistryTests: XCTestCase {
    func testMetadataLookupFindsRetainedEntryWithoutCreatingReplacement() {
        let registry = SessionRegistry()
        let device = RemoteDevice(name: "Shortcut QA", host: "127.0.0.1")
        let retained = TestSession.make(device: device, password: nil, isTemporary: true)
        retained.zoomScale = 2.5
        retained.isObserveOnly = true
        let entryID = registry.register(retained)
        XCTAssertEqual(registry.reusableSessionID(for: device), entryID)
        XCTAssertNotEqual(entryID, device.id)
        XCTAssertEqual(registry.sessions.count, 1)
        XCTAssertTrue(registry.session(for: entryID) === retained)
        XCTAssertTrue(retained.isObserveOnly)
        XCTAssertEqual(retained.zoomScale, 2.5)
        XCTAssertEqual(retained.client.state, .disconnected)
    }

    func testMetadataLookupRejectsChangedEndpointAndAccountButAllowsRename() {
        let registry = SessionRegistry()
        let device = RemoteDevice(name: "Shortcut QA", host: "127.0.0.1")
        let entryID = registry.register(TestSession.make(device: device, password: nil, isTemporary: true))
        var renamed = device
        renamed.name = "Renamed QA"
        XCTAssertEqual(registry.reusableSessionID(for: renamed), entryID)
        var changed = device
        changed.host = "127.0.0.2"
        XCTAssertNil(registry.reusableSessionID(for: changed))
        changed = device
        changed.port = 5901
        XCTAssertNil(registry.reusableSessionID(for: changed))
        changed = device
        changed.username = "synthetic-account"
        changed.authMethod = .macAccount
        XCTAssertNil(registry.reusableSessionID(for: changed))
    }

    func testMetadataLookupDoesNotFallbackToSameNameOrDeletedSession() {
        let registry = SessionRegistry()
        let device = RemoteDevice(name: "Shortcut QA", host: "127.0.0.1")
        let entryID = registry.register(TestSession.make(device: device, password: nil, isTemporary: true))
        let otherID = RemoteDevice(name: device.name, host: device.host)
        XCTAssertNil(registry.reusableSessionID(for: otherID))
        registry.remove(entryID)
        XCTAssertNil(registry.reusableSessionID(for: device))
    }

    func testMobileSelectionPreservesViewportsAndReleasesHiddenInput() {
        let registry = SessionRegistry()
        let first = TestSession.make(device: RemoteDevice(name: "First", host: "127.0.0.1"), password: nil, isTemporary: true)
        let second = TestSession.make(device: RemoteDevice(name: "Second", host: "127.0.0.1"), password: nil, isTemporary: true)
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
        let original = TestSession.make(device: device, password: nil, isTemporary: true)
        original.zoomScale = 2.5
        original.isObserveOnly = true
        let id = registry.register(original)
        let replacement = TestSession.make(device: device, password: nil, isTemporary: true)
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
        let first = TestSession.make(device: device, password: nil, isTemporary: true)
        let second = TestSession.make(device: device, password: nil, isTemporary: true)
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
        let third = TestSession.make(device: device, password: nil, isTemporary: true)
        registry.register(third, reuseExisting: false)
        XCTAssertEqual(registry.sessions.map(\.title), ["QA · 2", "QA · 3"], "Closing a window must not renumber live sessions")
    }

    func testTemporaryConnectionsAndDifferentDevicesAreDistinct() {
        let registry = SessionRegistry()
        let first = TestSession.make(device: RemoteDevice(name: "Temporary", host: "127.0.0.1"), password: nil, isTemporary: true)
        let second = TestSession.make(device: RemoteDevice(name: "Temporary", host: "127.0.0.1"), password: nil, isTemporary: true)
        XCTAssertNotEqual(registry.register(first), registry.register(second))
        XCTAssertEqual(registry.sessions.count, 2)
        XCTAssertTrue(registry.sessions.allSatisfy { $0.viewModel.isTemporary })
    }
}
