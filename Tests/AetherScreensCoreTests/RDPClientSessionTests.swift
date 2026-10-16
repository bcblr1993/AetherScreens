import XCTest
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
        XCTAssertEqual(client.framebuffer.width, 1280)
        XCTAssertEqual(client.framebuffer.height, 720)
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
