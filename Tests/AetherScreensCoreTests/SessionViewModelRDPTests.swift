import XCTest
import RDPKit
@testable import AetherScreensCore

final class SessionViewModelRDPTests: XCTestCase {
    @MainActor
    func testSessionViewModelInitializesWithRDPDevice() {
        let device = RemoteDevice(
            name: "Windows Server",
            host: "10.8.8.250",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "sprixin"
        )
        let session = SessionViewModel(device: device, password: "secretPassword", isTemporary: true)
        defer { session.endSession() }

        XCTAssertTrue(session.isRDP)
        XCTAssertNotNil(session.rdpClient)
        XCTAssertEqual(session.rdpClient?.host, "10.8.8.250")
        XCTAssertEqual(session.rdpClient?.port, 3389)
        XCTAssertEqual(session.rdpClient?.username, "sprixin")
        XCTAssertEqual(session.rdpClient?.password, "secretPassword")
        XCTAssertTrue(session.framebuffer === session.rdpClient?.framebuffer)
    }

    @MainActor
    func testSessionViewModelRDPStateForwarding() async throws {
        let device = RemoteDevice(
            name: "Windows Server",
            host: "10.8.8.250",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "sprixin"
        )
        let session = SessionViewModel(device: device, password: "123", isTemporary: true)
        defer { session.endSession() }

        guard let rdpClient = session.rdpClient else {
            XCTFail("RDP client should be instantiated")
            return
        }

        // Test state transitions
        rdpClient.onStateChanged?(.connecting)
        let connectingExp = expectation(description: "Connecting state")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { connectingExp.fulfill() }
        await fulfillment(of: [connectingExp], timeout: 1)
        XCTAssertEqual(session.sessionState, .connecting)

        rdpClient.onStateChanged?(.connected)
        let connectedExp = expectation(description: "Connected state")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { connectedExp.fulfill() }
        await fulfillment(of: [connectedExp], timeout: 1)
        XCTAssertEqual(session.sessionState, .connected)

        rdpClient.onStateChanged?(.failed("Authentication rejected"))
        let failedExp = expectation(description: "Failed state")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { failedExp.fulfill() }
        await fulfillment(of: [failedExp], timeout: 1)
        XCTAssertEqual(session.sessionState, .failed("Authentication rejected"))
    }

    @MainActor
    func testSessionViewModelRDPFrameUpdates() async throws {
        let device = RemoteDevice(
            name: "Windows Server",
            host: "10.8.8.250",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "sprixin"
        )
        let session = SessionViewModel(device: device, password: "123", isTemporary: true)
        defer { session.endSession() }

        guard let rdpClient = session.rdpClient else {
            XCTFail("RDP client should be instantiated")
            return
        }

        rdpClient.framebuffer.resize(newWidth: 1024, newHeight: 768)
        var frameUpdated = false
        let sub = session.frameUpdates.sink { frameUpdated = true }
        defer { sub.cancel() }

        rdpClient.onFrameUpdated?()

        for _ in 0..<40 where !session.hasReceivedFirstFrame {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertTrue(session.hasReceivedFirstFrame)
        XCTAssertTrue(frameUpdated)
        XCTAssertEqual(session.trackpadEngine.remoteWidth, 1024)
        XCTAssertEqual(session.trackpadEngine.remoteHeight, 768)
    }

    @MainActor
    func testSessionViewModelRDPClipboardForwarding() async throws {
        var writtenClipboard: String?
        let clipboardBox = Box("Initial local text")

        let device = RemoteDevice(
            name: "Windows Server",
            host: "10.8.8.250",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "sprixin"
        )
        let session = SessionViewModel(
            device: device,
            password: "123",
            isTemporary: true,
            clipboardWriter: { writtenClipboard = $0 },
            clipboardReader: { clipboardBox.value }
        )
        defer { session.endSession() }

        guard let rdpClient = session.rdpClient else {
            XCTFail("RDP client should be instantiated")
            return
        }

        // Simulate connected state
        rdpClient.onStateChanged?(.connected)
        let connExp = expectation(description: "Connected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { connExp.fulfill() }
        await fulfillment(of: [connExp], timeout: 1)

        // Incoming clipboard from remote Windows
        rdpClient.onClipboardReceived?("Copied from Windows Host")
        let clipExp = expectation(description: "Clipboard received")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { clipExp.fulfill() }
        await fulfillment(of: [clipExp], timeout: 1)

        XCTAssertEqual(writtenClipboard, "Copied from Windows Host")

        // Outgoing clipboard to remote Windows
        clipboardBox.value = "Local macOS text to Windows"
        session.sendLocalClipboardToRemote()
        XCTAssertNotNil(session.clipboardTransferNotice)
    }

    @MainActor
    func testSessionViewModelRDPPointerInputDispatch() {
        let device = RemoteDevice(
            name: "Windows Server",
            host: "10.8.8.250",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "sprixin"
        )
        let session = SessionViewModel(device: device, password: "123", isTemporary: true)
        defer { session.endSession() }

        guard let rdpClient = session.rdpClient else {
            XCTFail("RDP client should be instantiated")
            return
        }

        // Initially disconnected: pointer commands are not sent to server
        session.sendNativePointer(buttonMask: .left, x: 200, y: 300)
        XCTAssertNil(rdpClient.lastPointerPosition)

        // Update state to connected
        rdpClient.onStateChanged?(.connected)
        let drain = expectation(description: "State drain")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { drain.fulfill() }
        wait(for: [drain], timeout: 1)

        // Now pointer coordinates should update in rdpClient
        session.sendNativePointer(buttonMask: .left, x: 200, y: 300)
        XCTAssertEqual(rdpClient.lastPointerPosition?.0, 200)
        XCTAssertEqual(rdpClient.lastPointerPosition?.1, 300)
    }

    @MainActor
    func testSessionViewModelRDPDesktopResolutionAndRemoteSize() async throws {
        let device = RemoteDevice(
            name: "Win11 Workstation",
            host: "10.8.8.250",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "sprixin",
            desktopWidth: 1920,
            desktopHeight: 1080
        )
        let session = SessionViewModel(device: device, password: "123", isTemporary: true)
        defer { session.endSession() }

        guard let rdpClient = session.rdpClient else {
            XCTFail("RDP client should be instantiated")
            return
        }

        // Initial remote desktop size matches device preference
        XCTAssertEqual(session.remoteDesktopSize, CGSize(width: 1920, height: 1080))
        XCTAssertEqual(session.framebuffer.width, 1920)
        XCTAssertEqual(session.framebuffer.height, 1080)

        // Simulate remote desktop resize (e.g. 2560x1440)
        rdpClient.framebuffer.resize(newWidth: 2560, newHeight: 1440)
        rdpClient.onFrameUpdated?()

        let resizeExp = expectation(description: "Remote desktop size update")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { resizeExp.fulfill() }
        await fulfillment(of: [resizeExp], timeout: 1)

        XCTAssertEqual(session.remoteDesktopSize, CGSize(width: 2560, height: 1440))
        XCTAssertEqual(session.trackpadEngine.remoteWidth, 2560)
        XCTAssertEqual(session.trackpadEngine.remoteHeight, 1440)
    }

    @MainActor
    func testSessionViewModelRDPFileUploadAndDirectDrop() throws {
        let device = RemoteDevice(
            name: "Win11 Workstation",
            host: "10.8.8.250",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "sprixin"
        )
        let session = SessionViewModel(device: device, password: "123", isTemporary: true)
        defer { session.endSession() }

        guard let rdpClient = session.rdpClient else {
            XCTFail("RDP client should be instantiated")
            return
        }

        // Initially disconnected
        XCTAssertFalse(session.canStartFileUpload)

        // Connect
        rdpClient.simulateStateForTesting(.connected)
        let connExp = expectation(description: "Connected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { connExp.fulfill() }
        wait(for: [connExp], timeout: 1)

        // When connected, file upload & drag drop should be enabled for RDP
        XCTAssertTrue(session.canStartFileUpload)

        // Create temporary test file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-drop-\(UUID().uuidString).txt")
        try "Test file contents for RDP transfer".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Transfer dropped files
        session.transferDroppedFilesToRDP(urls: [tempURL])

        // Notice should be displayed
        XCTAssertNotNil(session.fileUploadNotice)
        XCTAssertTrue(session.fileUploadNotice?.contains(tempURL.lastPathComponent) == true)
    }

    @MainActor
    func testSessionViewModelRDPMouseCoordinatesAccurateWithoutDistortion() {
        let device = RemoteDevice(
            name: "Win11 Workstation",
            host: "10.8.8.250",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "sprixin",
            desktopWidth: 1920,
            desktopHeight: 1080
        )
        let session = SessionViewModel(device: device, password: "123", isTemporary: true)
        defer { session.endSession() }

        guard let rdpClient = session.rdpClient else {
            XCTFail("RDP client should be instantiated")
            return
        }

        rdpClient.onStateChanged?(.connected)
        let drain = expectation(description: "Connected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { drain.fulfill() }
        wait(for: [drain], timeout: 1)

        // Send pointer at exact 1080p desktop location
        session.sendNativePointer(buttonMask: .left, x: 1919, y: 1079)
        XCTAssertEqual(rdpClient.lastPointerPosition?.0, 1919)
        XCTAssertEqual(rdpClient.lastPointerPosition?.1, 1079)
    }

    @MainActor
    func testSessionViewModelRDPAudioHandlingAndMuteToggle() async throws {
        let device = RemoteDevice(
            name: "Win11 Workstation",
            host: "10.8.8.250",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "sprixin",
            remoteAudioEnabled: true
        )
        let session = SessionViewModel(device: device, password: "123", isTemporary: true)
        defer { session.endSession() }

        guard let rdpClient = session.rdpClient else {
            XCTFail("RDP client should be instantiated")
            return
        }

        XCTAssertTrue(session.isRemoteAudioEnabled)
        XCTAssertFalse(session.isRemoteAudioMuted)

        // Test mute toggle
        session.toggleRemoteAudioMute()
        XCTAssertTrue(session.isRemoteAudioMuted)

        session.setRemoteAudioMuted(false)
        XCTAssertFalse(session.isRemoteAudioMuted)

        // Connect
        rdpClient.onStateChanged?(.connected)
        let drain = expectation(description: "Connected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { drain.fulfill() }
        await fulfillment(of: [drain], timeout: 1)

        // Simulate audio sample delivery
        let format = try RDPAudioFormat(
            formatTag: RDPAudioFormatTag.pcm,
            channelCount: 2,
            samplesPerSecond: 44100,
            averageBytesPerSecond: 176400,
            blockAlign: 4,
            bitsPerSample: 16
        )
        let sample = RDPAudioSample(
            format: format,
            timestamp: 0,
            blockNo: 0,
            data: Data(repeating: 0, count: 256),
            receivedAt: Date()
        )
        rdpClient.simulateAudioSampleForTesting(sample)

        // Mute and deliver sample again (should not crash and cleanly drop)
        session.setRemoteAudioMuted(true)
        rdpClient.simulateAudioSampleForTesting(sample)

        session.endSession()
    }

    @MainActor
    func testSessionViewModelRDPAutoFitAndResolutionUpdate() {
        let device = RemoteDevice(
            name: "Win11 Workstation",
            host: "10.8.8.250",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "sprixin",
            autoFitResolution: true
        )
        let session = SessionViewModel(device: device, password: "123", isTemporary: true)
        defer { session.endSession() }

        XCTAssertTrue(session.autoFitResolution)
        session.toggleAutoFitResolution()
        XCTAssertFalse(session.autoFitResolution)
        session.toggleAutoFitResolution()
        XCTAssertTrue(session.autoFitResolution)

        // Resolution update does not crash when disconnected or connected
        session.updateRemoteDesktopResolution(width: 1440, height: 900)
    }
}


private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
