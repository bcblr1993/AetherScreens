import XCTest
import RDPKit
@testable import AetherScreensCore

final class RDPClientSessionTests: XCTestCase {

    func testRDPClientInitialStateAndProperties() {
        let client = RDPClient(host: "10.8.8.250", port: 3389, username: "sprixin", password: "secretpassword")
        XCTAssertEqual(client.host, "10.8.8.250")
        XCTAssertEqual(client.port, 3389)
        XCTAssertEqual(client.username, "sprixin")
        XCTAssertEqual(client.password, "secretpassword")
        XCTAssertEqual(client.state, .disconnected)
        XCTAssertNotNil(client.framebuffer)
        XCTAssertEqual(client.framebuffer.width, 1920)
        XCTAssertEqual(client.framebuffer.height, 1080)
    }

    func testRDPClientPublishLocalFilesSafeWhenDisconnected() {
        let client = RDPClient(host: "10.8.8.250", port: 3389, username: "sprixin", password: "123")
        let file = RDPClipboardLocalFile(fileName: "test.txt", contents: Data("hello".utf8))
        XCTAssertFalse(client.publishLocalFiles([file]))
    }

    func testRemoteDeviceDesktopResolutionCodable() throws {
        let device = RemoteDevice(
            name: "Win11 Workstation",
            host: "192.168.1.50",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "admin",
            desktopWidth: 2560,
            desktopHeight: 1440
        )
        let data = try JSONEncoder().encode(device)
        let decoded = try JSONDecoder().decode(RemoteDevice.self, from: data)
        XCTAssertEqual(decoded.desktopWidth, 2560)
        XCTAssertEqual(decoded.desktopHeight, 1440)

        // Backward compatibility: JSON without desktopWidth/desktopHeight decodes nil
        let legacyJSON = """
        {
            "id": "\(UUID().uuidString)",
            "name": "Legacy Box",
            "host": "192.168.1.60",
            "port": 3389,
            "deviceType": "Windows",
            "remoteProtocol": "RDP",
            "isOnline": true,
            "isTailscaleNode": false,
            "isFavorite": false,
            "tags": []
        }
        """.data(using: .utf8)!
        let legacyDecoded = try JSONDecoder().decode(RemoteDevice.self, from: legacyJSON)
        XCTAssertNil(legacyDecoded.desktopWidth)
        XCTAssertNil(legacyDecoded.desktopHeight)
    }

    func testRDPClientConnectWithoutCredentialsFailsImmediately() {
        let client = RDPClient(host: "10.8.8.250", port: 3389, username: "", password: "")
        client.connect()

        if case .failed(let reason) = client.state {
            XCTAssertTrue(reason.contains("username") || reason.contains("credential") || reason.contains("account"))
        } else {
            XCTFail("Expected .failed state due to missing credentials, got \(client.state)")
        }
    }

    func testRDPClientDisconnectResetsState() {
        let client = RDPClient(host: "10.8.8.250", port: 3389, username: "sprixin", password: "123")
        client.disconnect()
        XCTAssertEqual(client.state, .disconnected)
    }

    func testRDPClientPointerAndKeyboardEventsDoNotCrashWhenDisconnected() {
        let client = RDPClient(host: "10.8.8.250", port: 3389, username: "sprixin", password: "123")
        // Should safely no-op when disconnected without crashing
        client.sendPointerEvent(buttonMask: .left, x: 100, y: 100)
        client.sendKeyEvent(down: true, keySym: 0xff0d) // Enter
        client.sendKeyEvent(down: false, keySym: 0xff0d)
        client.sendText("hello")
        XCTAssertEqual(client.state, .disconnected)
    }
}

