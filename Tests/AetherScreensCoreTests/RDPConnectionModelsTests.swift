import XCTest
@testable import AetherScreensCore

final class RDPConnectionModelsTests: XCTestCase {

    func testRemoteProtocolDefaultsAndPort() {
        XCTAssertEqual(RemoteDevice.RemoteProtocol.rfb.defaultPort, 5900)
        XCTAssertEqual(RemoteDevice.RemoteProtocol.rdp.defaultPort, 3389)
    }

    func testRemoteDeviceInitializationWithRDPProtocol() {
        let rdpDevice = RemoteDevice(
            name: "Windows Server",
            host: "192.0.2.50",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "rdpuser"
        )
        XCTAssertEqual(rdpDevice.remoteProtocol, .rdp)
        XCTAssertEqual(rdpDevice.port, 3389)
        XCTAssertEqual(rdpDevice.deviceType, .windows)
        XCTAssertEqual(rdpDevice.username, "rdpuser")
        XCTAssertEqual(rdpDevice.authMethod, .windowsCredentials)
    }

    func testRemoteDeviceCodableBackwardCompatibility() throws {
        // Legacy JSON without `remoteProtocol` field:
        // Case 1: port is 3389 -> infers .rdp
        let json3389 = """
        {
            "id": "\(UUID().uuidString)",
            "name": "Win Host",
            "host": "192.0.2.50",
            "port": 3389,
            "deviceType": "Windows",
            "authMethod": "macOS Account",
            "username": "rdpuser",
            "isOnline": true,
            "isTailscaleNode": false
        }
        """.data(using: .utf8)!

        let decoded3389 = try JSONDecoder().decode(RemoteDevice.self, from: json3389)
        XCTAssertEqual(decoded3389.remoteProtocol, .rdp)

        // Case 2: port is 5900 -> defaults to .rfb
        let json5900 = """
        {
            "id": "\(UUID().uuidString)",
            "name": "Mac Studio",
            "host": "192.168.1.100",
            "port": 5900,
            "deviceType": "macOS",
            "authMethod": "macOS Account",
            "username": "admin",
            "isOnline": true,
            "isTailscaleNode": false
        }
        """.data(using: .utf8)!

        let decoded5900 = try JSONDecoder().decode(RemoteDevice.self, from: json5900)
        XCTAssertEqual(decoded5900.remoteProtocol, .rfb)
    }

    func testConnectionRequestForRDP() throws {
        let request = try XCTUnwrap(ConnectionRequest(
            host: "192.0.2.50",
            port: "3389",
            name: "Win10",
            username: "rdpuser",
            password: "secretpassword",
            type: .windows,
            remoteProtocol: .rdp
        ))

        XCTAssertEqual(request.device.remoteProtocol, .rdp)
        XCTAssertEqual(request.device.port, 3389)
        XCTAssertEqual(request.device.username, "rdpuser")
        XCTAssertEqual(request.device.authMethod, .windowsCredentials)
        XCTAssertEqual(request.password, "secretpassword")
    }

    func testConnectionLinkSupportsRDPScheme() throws {
        let url = try XCTUnwrap(URL(string: "rdp://rdpuser:test-pass@192.0.2.50:3389"))
        let link = try ConnectionLink(url: url)
        let resolved = try link.resolve(devices: []) { _ in nil }

        XCTAssertEqual(resolved.device.host, "192.0.2.50")
        XCTAssertEqual(resolved.device.port, 3389)
        XCTAssertEqual(resolved.device.username, "rdpuser")
        XCTAssertEqual(resolved.device.remoteProtocol, .rdp)
        XCTAssertEqual(resolved.password, "test-pass")
        XCTAssertTrue(resolved.isTemporary)
    }

    func testConnectionRequestProtocolResolution() throws {
        // Windows on port 3389 without explicit protocol should resolve to .rdp
        let req1 = try XCTUnwrap(ConnectionRequest(
            host: "192.0.2.50",
            port: "3389",
            name: "Win Default",
            username: "rdpuser",
            password: "123",
            type: .windows
        ))
        XCTAssertEqual(req1.device.remoteProtocol, .rdp)
        XCTAssertEqual(req1.device.authMethod, .windowsCredentials)

        // Explicit .rfb on port 3389 should be honored
        let req2 = try XCTUnwrap(ConnectionRequest(
            host: "192.0.2.50",
            port: "3389",
            name: "Win VNC",
            username: "rdpuser",
            password: "123",
            type: .windows,
            remoteProtocol: .rfb
        ))
        XCTAssertEqual(req2.device.remoteProtocol, .rfb)
        XCTAssertEqual(req2.device.authMethod, .macAccount)
    }

    func testDeviceStoreSavesAndRetrievesRDPDevice() throws {
        let store = DeviceStore(userDefaults: UserDefaults(suiteName: "qa.rdp.store.\(UUID().uuidString)")!)
        let device = RemoteDevice(
            name: "Win 10 QA",
            host: "192.0.2.50",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "rdpuser"
        )

        XCTAssertTrue(store.addDevice(device))
        let fetched = try XCTUnwrap(store.devices.first(where: { $0.id == device.id }))
        XCTAssertEqual(fetched.remoteProtocol, .rdp)
        XCTAssertEqual(fetched.deviceType, .windows)
        XCTAssertEqual(fetched.authMethod, .windowsCredentials)
        XCTAssertEqual(fetched.port, 3389)
        XCTAssertEqual(fetched.username, "rdpuser")
    }
}
