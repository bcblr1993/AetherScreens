import XCTest
@testable import AetherScreensCore

final class Phase6URLSchemeTests: XCTestCase {

    func testScreensDirectURLAndSavedURLCompatibility() throws {
        let directURL = try XCTUnwrap(URL(string: "screens://ops:s3cr3t@10.0.1.25:5901?observe=true"))
        let directResolved = try ConnectionLink(url: directURL).resolve(devices: []) { _ in nil }
        XCTAssertEqual(directResolved.device.host, "10.0.1.25")
        XCTAssertEqual(directResolved.device.port, 5901)
        XCTAssertEqual(directResolved.device.username, "ops")
        XCTAssertEqual(directResolved.password, "s3cr3t")
        XCTAssertEqual(directResolved.observeOnly, true)
        XCTAssertTrue(directResolved.isTemporary)

        let savedDevice = RemoteDevice(name: "Office iMac", host: "10.0.1.88", port: 5900)
        let savedURL = try XCTUnwrap(URL(string: "screens://saved/\(savedDevice.id.uuidString)?observe=false"))
        let savedResolved = try ConnectionLink(url: savedURL).resolve(devices: [savedDevice]) { _ in "keychain-pw" }
        XCTAssertEqual(savedResolved.device.id, savedDevice.id)
        XCTAssertEqual(savedResolved.password, "keychain-pw")
        XCTAssertEqual(savedResolved.observeOnly, false)
    }

    func testConnectURLSupportsSSHTunnelParameters() throws {
        let urlString = "screens://connect?host=10.20.30.40&port=3389&protocol=RDP&name=Cloud%20Win&username=admin&sshHost=bastion.corp.internal&sshPort=2222&sshUser=deploy"
        let url = try XCTUnwrap(URL(string: urlString))
        let resolved = try ConnectionLink(url: url).resolve(devices: []) { _ in nil }

        XCTAssertEqual(resolved.device.name, "Cloud Win")
        XCTAssertEqual(resolved.device.host, "10.20.30.40")
        XCTAssertEqual(resolved.device.port, 3389)
        XCTAssertEqual(resolved.device.remoteProtocol, .rdp)
        XCTAssertEqual(resolved.device.deviceType, .windows)
        XCTAssertEqual(resolved.device.username, "admin")

        let ssh = try XCTUnwrap(resolved.device.ssh)
        XCTAssertEqual(ssh.server.host, "bastion.corp.internal")
        XCTAssertEqual(ssh.server.port, 2222)
        XCTAssertEqual(ssh.username, "deploy")
    }

    func testShareableConnectURLRoundTripsWithoutCredentials() throws {
        let sshAddress = try XCTUnwrap(SSHServerAddress(host: "jump.example.com", port: 2200))
        let sshSettings = try XCTUnwrap(SSHConnectionSettings(
            server: sshAddress,
            username: "jumpuser",
            authentication: .password
        ))
        let device = RemoteDevice(
            name: "Prod Bastion Target",
            host: "192.168.10.99",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "alice",
            ssh: sshSettings
        )

        let shareableURL = ConnectionLink.connectURL(for: device, observeOnly: true)
        XCTAssertFalse(shareableURL.absoluteString.contains("password"))

        let resolved = try ConnectionLink(url: shareableURL).resolve(devices: []) { _ in nil }
        XCTAssertEqual(resolved.device.name, "Prod Bastion Target")
        XCTAssertEqual(resolved.device.host, "192.168.10.99")
        XCTAssertEqual(resolved.device.port, 3389)
        XCTAssertEqual(resolved.device.remoteProtocol, .rdp)
        XCTAssertEqual(resolved.device.username, "alice")
        XCTAssertEqual(resolved.observeOnly, true)
        XCTAssertEqual(resolved.device.ssh?.server.host, "jump.example.com")
        XCTAssertEqual(resolved.device.ssh?.server.port, 2200)
        XCTAssertEqual(resolved.device.ssh?.username, "jumpuser")
    }
}
