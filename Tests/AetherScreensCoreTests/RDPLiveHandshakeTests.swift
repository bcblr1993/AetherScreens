import XCTest
@testable import AetherScreensCore

final class RDPLiveHandshakeTests: XCTestCase {

    var targetHost = ""
    var targetPort: UInt16 = 3389
    var targetUsername = ""
    var targetPassword = ""

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["AETHERSCREENS_RDP_LIVE_HOST"], !host.isEmpty else {
            throw XCTSkip("Set AETHERSCREENS_RDP_LIVE_HOST to run live RDP tests")
        }
        targetHost = host
        if let port = env["AETHERSCREENS_RDP_LIVE_PORT"].flatMap(UInt16.init) {
            targetPort = port
        }
        targetUsername = env["AETHERSCREENS_RDP_LIVE_USERNAME"] ?? "sprixin"
        targetPassword = env["AETHERSCREENS_RDP_LIVE_PASSWORD"] ?? "123456"
    }

    @MainActor
    func testLiveRDPConnectionReceivesFrame() async throws {
        let client = RDPClient(
            host: targetHost,
            port: targetPort,
            username: targetUsername,
            password: targetPassword
        )

        let frameExpectation = expectation(description: "RDP frame received")
        frameExpectation.assertForOverFulfill = false

        client.onFrameUpdated = {
            frameExpectation.fulfill()
        }

        client.connect()

        await fulfillment(of: [frameExpectation], timeout: 20)

        XCTAssertTrue(client.framebuffer.width > 0)
        XCTAssertTrue(client.framebuffer.height > 0)

        client.disconnect()
        XCTAssertEqual(client.state, .disconnected)
    }

    @MainActor
    func testLiveSessionViewModelConnectsAndReceivesFrame() async throws {
        let device = RemoteDevice(
            name: "Live Windows Host",
            host: targetHost,
            port: targetPort,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: targetUsername
        )
        let session = SessionViewModel(device: device, password: targetPassword, isTemporary: true)
        defer { session.requestDisconnect() }

        let frameExpectation = expectation(description: "SessionViewModel receives RDP frame")
        frameExpectation.assertForOverFulfill = false

        let sub = session.frameUpdates.sink {
            frameExpectation.fulfill()
        }
        defer { sub.cancel() }

        session.startSession()

        await fulfillment(of: [frameExpectation], timeout: 20)

        XCTAssertTrue(session.hasReceivedFirstFrame)
        XCTAssertEqual(session.sessionState, .connected)
        XCTAssertTrue(session.framebuffer.width > 0)
        XCTAssertTrue(session.framebuffer.height > 0)
    }
}
