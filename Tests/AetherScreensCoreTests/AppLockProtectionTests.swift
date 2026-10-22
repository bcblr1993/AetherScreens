import XCTest
@testable import AetherScreensCore

final class AppLockProtectionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: SessionViewModel.autoClipboardSyncKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SessionViewModel.autoClipboardSyncKey)
        super.tearDown()
    }

    // MARK: - App lock

    @MainActor
    func testBlocksAccessOnlyWhenEnabledAndLocked() {
        let defaults = UserDefaults(suiteName: "test.applock.\(UUID().uuidString)")!
        let service = AppLockService(userDefaults: defaults, authEvaluator: { _ in true }, biometryEvaluator: { .none })
        XCTAssertFalse(service.blocksAccess)
        service.isLockEnabled = true
        service.lock()
        XCTAssertTrue(service.blocksAccess)
        service.isLockEnabled = false
        XCTAssertFalse(service.blocksAccess)
    }

    @MainActor
    func testConcurrentUnlockRequestsShareOneAuthentication() async {
        let defaults = UserDefaults(suiteName: "test.applock.\(UUID().uuidString)")!
        let prompts = Counter()
        let service = AppLockService(userDefaults: defaults, authEvaluator: { _ in
            prompts.increment()
            try? await Task.sleep(nanoseconds: 50_000_000)
            return true
        }, biometryEvaluator: { .none })
        service.isLockEnabled = true
        service.lock()

        async let first = service.unlock()
        async let second = service.unlock()
        async let third = service.unlock()
        let results = await [first, second, third]

        XCTAssertEqual(results, [true, true, true])
        XCTAssertEqual(prompts.value, 1, "Each locked window must not open its own Touch ID prompt")
        XCTAssertFalse(service.blocksAccess)
    }

    // MARK: - Locked sessions

    @MainActor
    func testLockedSessionStopsInputAndClipboardInBothDirections() async throws {
        let clipboard = Box("local text")
        let written = Box<String?>(nil)
        let session = try await connectedRDPSession(reader: { clipboard.value }, writer: { written.value = $0 })
        defer { session.endSession() }

        session.setSuspendedByAppLock(true)
        XCTAssertFalse(session.allowsRemoteInput)

        session.syncLocalClipboardIfNeeded()
        XCTAssertNil(session.lastSentClipboardText, "Locked sessions must not send the local clipboard")

        session.rdpClient?.onClipboardReceived?("remote secret")
        try await drainMainQueue()
        XCTAssertNil(written.value, "Locked sessions must not write remote text into the local clipboard")

        session.setSuspendedByAppLock(false)
        XCTAssertTrue(session.allowsRemoteInput)
        XCTAssertEqual(session.lastSentClipboardText, "local text", "Unlocking resumes clipboard sync")
    }

    // MARK: - Clipboard privacy

    @MainActor
    func testConcealedClipboardIsNeverAutoSynced() async throws {
        let session = try await connectedRDPSession(reader: { "hunter2" }, concealed: { true })
        defer { session.endSession() }

        session.syncLocalClipboardIfNeeded()
        XCTAssertNil(session.lastSentClipboardText)
    }

    @MainActor
    func testUnchangedPasteboardIsNotReadAgain() async throws {
        let reads = Counter()
        let changeCount = Box(1)
        let session = try await connectedRDPSession(
            reader: { reads.increment(); return "copied \(changeCount.value)" },
            changeCount: { changeCount.value }
        )
        defer { session.endSession() }

        session.syncLocalClipboardIfNeeded()
        let readsAfterFirstSync = reads.value
        XCTAssertEqual(session.lastSentClipboardText, "copied 1")

        session.syncLocalClipboardIfNeeded()
        session.syncLocalClipboardIfNeeded()
        XCTAssertEqual(reads.value, readsAfterFirstSync, "Polling must not read contents until the pasteboard changes")

        changeCount.value = 2
        session.syncLocalClipboardIfNeeded()
        XCTAssertEqual(session.lastSentClipboardText, "copied 2")
    }

    func testPasswordManagerMarkersAreRecognised() {
        XCTAssertTrue(SessionViewModel.concealedPasteboardTypes.contains("org.nspasteboard.ConcealedType"))
        XCTAssertTrue(SessionViewModel.concealedPasteboardTypes.contains("org.nspasteboard.TransientType"))
    }

    // MARK: - Helpers

    @MainActor
    private func connectedRDPSession(
        reader: @escaping @MainActor @Sendable () -> String?,
        writer: (@MainActor @Sendable (String) -> Void)? = nil,
        changeCount: (@MainActor @Sendable () -> Int?)? = nil,
        concealed: (@MainActor @Sendable () -> Bool)? = nil
    ) async throws -> SessionViewModel {
        let device = RemoteDevice(name: "Windows", host: "192.0.2.50", port: 3389, deviceType: .windows,
                                  remoteProtocol: .rdp, authMethod: .windowsCredentials, username: "rdpuser")
        let session = SessionViewModel(device: device, password: "test-pass", isTemporary: true,
                                       clipboardWriter: writer ?? { _ in }, clipboardReader: reader,
                                       clipboardFilesReader: { nil },
                                       clipboardChangeCount: changeCount, clipboardIsConcealed: concealed)
        session.rdpClient?.onStateChanged?(.connected)
        try await drainMainQueue()
        return session
    }

    private func drainMainQueue() async throws {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 1)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count += 1; lock.unlock() }
}

private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
