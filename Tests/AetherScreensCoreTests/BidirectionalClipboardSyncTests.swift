import XCTest
@testable import AetherScreensCore

final class BidirectionalClipboardSyncTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: SessionViewModel.autoClipboardSyncKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SessionViewModel.autoClipboardSyncKey)
        super.tearDown()
    }

    @MainActor
    func testAutoClipboardSyncEnabledByDefault() {
        let device = RemoteDevice(name: "Mac mini", host: "127.0.0.1", port: 5900)
        let session = SessionViewModel(device: device, password: nil, isTemporary: true)
        defer { session.endSession() }

        XCTAssertTrue(session.isAutoClipboardSyncEnabled)
        XCTAssertNil(session.lastSentClipboardText)
        XCTAssertNil(session.lastReceivedClipboardText)
    }

    @MainActor
    func testOutgoingAutoSyncSendsToRemoteWhenLocalChanges() async throws {
        let clipboardBox = Box("Copied on local Mac")
        let device = RemoteDevice(
            name: "Windows Server",
            host: "192.0.2.50",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "admin"
        )
        let session = SessionViewModel(
            device: device,
            password: "123",
            isTemporary: true,
            clipboardReader: { clipboardBox.value }
        )
        defer { session.endSession() }

        guard let rdpClient = session.rdpClient else {
            XCTFail("RDP client should exist")
            return
        }

        // Simulate connected state
        rdpClient.onStateChanged?(.connected)
        let drain = expectation(description: "Drain state")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { drain.fulfill() }
        await fulfillment(of: [drain], timeout: 1)

        // Trigger automatic sync
        session.syncLocalClipboardIfNeeded()

        XCTAssertEqual(session.lastSentClipboardText, "Copied on local Mac")

        // Calling it again without changes should not re-send
        clipboardBox.value = "Copied on local Mac"
        session.syncLocalClipboardIfNeeded()
        XCTAssertEqual(session.lastSentClipboardText, "Copied on local Mac")
    }

    @MainActor
    func testPreventEchoLoopWhenRemoteTextReceived() async throws {
        var writtenClipboard: String?
        let clipboardBox = Box("Local text")
        let device = RemoteDevice(
            name: "Windows Server",
            host: "192.0.2.50",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "admin"
        )
        let session = SessionViewModel(
            device: device,
            password: "123",
            isTemporary: true,
            clipboardWriter: { writtenClipboard = $0; clipboardBox.value = $0 },
            clipboardReader: { clipboardBox.value }
        )
        defer { session.endSession() }

        guard let rdpClient = session.rdpClient else {
            XCTFail("RDP client should exist")
            return
        }

        rdpClient.onStateChanged?(.connected)
        let connExp = expectation(description: "Connected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { connExp.fulfill() }
        await fulfillment(of: [connExp], timeout: 1)

        // Remote host sends clipboard update
        rdpClient.onClipboardReceived?("Text from Remote Server")
        let clipExp = expectation(description: "Clipboard received")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { clipExp.fulfill() }
        await fulfillment(of: [clipExp], timeout: 1)

        XCTAssertEqual(writtenClipboard, "Text from Remote Server")
        XCTAssertEqual(session.lastReceivedClipboardText, "Text from Remote Server")

        // Now local clipboard box has "Text from Remote Server"
        // syncLocalClipboardIfNeeded must NOT send it back as an echo
        session.syncLocalClipboardIfNeeded()
        XCTAssertNil(session.lastSentClipboardText, "Should not echo received remote text back to remote server")
    }

    @MainActor
    func testObserveModeBlocksAutoClipboardSync() async throws {
        let clipboardBox = Box("Confidential local text")
        let device = RemoteDevice(
            name: "Windows Server",
            host: "192.0.2.50",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "admin"
        )
        let session = SessionViewModel(
            device: device,
            password: "123",
            isTemporary: true,
            clipboardReader: { clipboardBox.value }
        )
        defer { session.endSession() }

        guard let rdpClient = session.rdpClient else {
            XCTFail("RDP client should exist")
            return
        }

        rdpClient.onStateChanged?(.connected)
        let connExp = expectation(description: "Connected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { connExp.fulfill() }
        await fulfillment(of: [connExp], timeout: 1)

        session.isObserveOnly = true
        session.syncLocalClipboardIfNeeded()

        XCTAssertNil(session.lastSentClipboardText, "Observe mode must prevent clipboard transmission")
    }

    @MainActor
    func testDisablingAutoClipboardSyncPreventsAutomaticDispatch() async throws {
        let clipboardBox = Box("Text to keep local")
        let device = RemoteDevice(
            name: "Windows Server",
            host: "192.0.2.50",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "admin"
        )
        let session = SessionViewModel(
            device: device,
            password: "123",
            isTemporary: true,
            clipboardReader: { clipboardBox.value }
        )
        defer { session.endSession() }

        guard let rdpClient = session.rdpClient else {
            XCTFail("RDP client should exist")
            return
        }

        rdpClient.onStateChanged?(.connected)
        let connExp = expectation(description: "Connected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { connExp.fulfill() }
        await fulfillment(of: [connExp], timeout: 1)

        session.isAutoClipboardSyncEnabled = false
        session.syncLocalClipboardIfNeeded()

        XCTAssertNil(session.lastSentClipboardText)
    }

    @MainActor
    func testImmediateSyncBeforeCommandVShortcut() async throws {
        let clipboardBox = Box("Instant Cmd+V Text")
        let device = RemoteDevice(
            name: "Windows Server",
            host: "192.0.2.50",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "admin"
        )
        let session = SessionViewModel(
            device: device,
            password: "123",
            isTemporary: true,
            clipboardReader: { clipboardBox.value }
        )
        defer { session.endSession() }

        guard let rdpClient = session.rdpClient else {
            XCTFail("RDP client should exist")
            return
        }

        rdpClient.onStateChanged?(.connected)
        let connExp = expectation(description: "Connected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { connExp.fulfill() }
        await fulfillment(of: [connExp], timeout: 1)

        XCTAssertNil(session.lastSentClipboardText)

        // User hits Cmd+V
        session.sendCommandShortcut("v")

        XCTAssertEqual(session.lastSentClipboardText, "Instant Cmd+V Text")
    }

    @MainActor
    func testImmediateSyncBeforeRawKeyShortcut() async throws {
        let clipboardBox = Box("Instant Raw Key Text")
        let device = RemoteDevice(
            name: "Windows Server",
            host: "192.0.2.50",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "admin"
        )
        let session = SessionViewModel(
            device: device,
            password: "123",
            isTemporary: true,
            clipboardReader: { clipboardBox.value }
        )
        defer { session.endSession() }

        guard let rdpClient = session.rdpClient else {
            XCTFail("RDP client should exist")
            return
        }

        rdpClient.onStateChanged?(.connected)
        let connExp = expectation(description: "Connected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { connExp.fulfill() }
        await fulfillment(of: [connExp], timeout: 1)

        XCTAssertNil(session.lastSentClipboardText)

        // Lock Cmd/Ctrl modifier and send 'v'
        session.cmdState = .locked
        session.sendNativeKey(down: true, keySym: MacKeyMap.v)

        XCTAssertEqual(session.lastSentClipboardText, "Instant Raw Key Text")
    }

    @MainActor
    func testPreventEchoLoopWithLineEndingDifferences() async throws {
        var writtenClipboard: String?
        let clipboardBox = Box("Initial")
        let device = RemoteDevice(
            name: "Windows Server",
            host: "192.0.2.50",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "admin"
        )
        let session = SessionViewModel(
            device: device,
            password: "123",
            isTemporary: true,
            clipboardWriter: { writtenClipboard = $0; clipboardBox.value = $0.replacingOccurrences(of: "\r\n", with: "\n") },
            clipboardReader: { clipboardBox.value }
        )
        defer { session.endSession() }

        guard let rdpClient = session.rdpClient else {
            XCTFail("RDP client should exist")
            return
        }

        rdpClient.onStateChanged?(.connected)
        let connExp = expectation(description: "Connected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { connExp.fulfill() }
        await fulfillment(of: [connExp], timeout: 1)

        // Windows server sends clipboard with CRLF
        rdpClient.onClipboardReceived?("Line 1\r\nLine 2")
        let clipExp = expectation(description: "Clipboard received")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { clipExp.fulfill() }
        await fulfillment(of: [clipExp], timeout: 1)

        XCTAssertEqual(writtenClipboard, "Line 1\r\nLine 2")
        // Local clipboard reader returns normalized LF ("Line 1\nLine 2")
        XCTAssertEqual(clipboardBox.value, "Line 1\nLine 2")

        // Auto-sync should not treat this as a different local text and re-upload it
        session.syncLocalClipboardIfNeeded()
        XCTAssertNil(session.lastSentClipboardText, "Line ending differences between CRLF and LF must not cause echo loop")
    }

    @MainActor
    func testWindowsRDPCommandShortcutTranslatesToControl() async throws {
        let device = RemoteDevice(
            name: "Windows Server",
            host: "192.0.2.50",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "admin"
        )
        let session = SessionViewModel(device: device, password: "123", isTemporary: true)
        defer { session.endSession() }

        guard let rdpClient = session.rdpClient else {
            XCTFail("RDP client should exist")
            return
        }

        rdpClient.onStateChanged?(.connected)
        let connExp = expectation(description: "Connected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { connExp.fulfill() }
        await fulfillment(of: [connExp], timeout: 1)

        // On Windows RDP, shortcut commands like 'c' or 'v' should use Control, not Command
        session.sendCommandShortcut("c")
        // Control was pressed and released, Command was not pressed
        XCTAssertFalse(session.isCmdActive)
        XCTAssertFalse(session.isCtrlActive)
    }

    func testRDPScancodeMappingForLettersAndShortcuts() {
        // Test keySym to scancode mappings
        XCTAssertEqual(RDPClient.mapKeySymToScancode(MacKeyMap.v)?.code, 0x2F)
        XCTAssertEqual(RDPClient.mapKeySymToScancode(0x0063)?.code, 0x2E) // 'c'
        XCTAssertEqual(RDPClient.mapKeySymToScancode(0x0078)?.code, 0x2D) // 'x'
        XCTAssertEqual(RDPClient.mapKeySymToScancode(0x0061)?.code, 0x1E) // 'a'
        XCTAssertEqual(RDPClient.mapKeySymToScancode(0x007A)?.code, 0x2C) // 'z'
        XCTAssertEqual(RDPClient.mapKeySymToScancode(0x0073)?.code, 0x1F) // 's'
        XCTAssertEqual(RDPClient.mapKeySymToScancode(MacKeyMap.controlLeft)?.code, 0x1D)
    }
}


private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
