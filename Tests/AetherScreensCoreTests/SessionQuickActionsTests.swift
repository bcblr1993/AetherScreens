import XCTest
@testable import AetherScreensCore

final class SessionQuickActionsTests: XCTestCase {
    @MainActor
    func testTriggerHotCornersDispatchesPointerToExactCoordinates() async throws {
        let device = RemoteDevice(
            name: "Windows Server",
            host: "10.8.8.250",
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

        // Simulate connected state
        rdpClient.onStateChanged?(.connected)
        let connExp = expectation(description: "Connected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { connExp.fulfill() }
        await fulfillment(of: [connExp], timeout: 1)

        // Remote size default in RDP client is 1024x768
        let expectedMaxX = UInt16(clamping: rdpClient.framebuffer.width - 1)
        let expectedMaxY = UInt16(clamping: rdpClient.framebuffer.height - 1)

        // Top Left
        session.triggerHotCorner(.topLeft)
        XCTAssertEqual(rdpClient.lastPointerPosition?.0, 0)
        XCTAssertEqual(rdpClient.lastPointerPosition?.1, 0)

        // Top Right
        session.triggerHotCorner(.topRight)
        XCTAssertEqual(rdpClient.lastPointerPosition?.0, expectedMaxX)
        XCTAssertEqual(rdpClient.lastPointerPosition?.1, 0)

        // Bottom Left
        session.triggerHotCorner(.bottomLeft)
        XCTAssertEqual(rdpClient.lastPointerPosition?.0, 0)
        XCTAssertEqual(rdpClient.lastPointerPosition?.1, expectedMaxY)

        // Bottom Right
        session.triggerHotCorner(.bottomRight)
        XCTAssertEqual(rdpClient.lastPointerPosition?.0, expectedMaxX)
        XCTAssertEqual(rdpClient.lastPointerPosition?.1, expectedMaxY)
    }

    @MainActor
    func testHotCornerBlockedInObserveMode() async throws {
        let device = RemoteDevice(
            name: "Windows Server",
            host: "10.8.8.250",
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

        session.isObserveOnly = true
        session.triggerHotCorner(.topRight)
        XCTAssertNil(rdpClient.lastPointerPosition, "Observe mode must block hot corner pointer dispatch")
    }

    @MainActor
    func testTriggerSystemActionsWhenConnected() async throws {
        let device = RemoteDevice(
            name: "Windows Server",
            host: "10.8.8.250",
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

        // Trigger Ctrl-Alt-Delete
        session.triggerSystemAction(.controlAltDelete)

        // Trigger Log Out
        session.triggerSystemAction(.logOut)

        // Trigger Mission Control shortcut
        session.executeShortcut(.missionControl)

        // Trigger Show Desktop shortcut
        session.executeShortcut(.showDesktop)
    }
}
