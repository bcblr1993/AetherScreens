import XCTest
@testable import AetherScreensCore

final class Phase3NetworkingTests: XCTestCase {

    func testTailscaleDeviceOSInferenceForWindowsAndLinux() {
        let winNode = TailscaleDevice(
            id: "node_win",
            name: "win-pc.tailnet.ts.net",
            hostname: "Gaming-PC",
            addresses: ["100.90.1.15"],
            os: "windows",
            connectedToControl: true
        )
        XCTAssertTrue(winNode.isWindows)
        XCTAssertFalse(winNode.isMac)

        let winDevice = RemoteDevice.fromTailscaleDevice(winNode)
        XCTAssertNotNil(winDevice)
        XCTAssertEqual(winDevice?.deviceType, .windows)
        XCTAssertEqual(winDevice?.remoteProtocol, .rdp)
        XCTAssertEqual(winDevice?.port, 3389)
        XCTAssertEqual(winDevice?.authMethod, .windowsCredentials)

        let linuxNode = TailscaleDevice(
            id: "node_linux",
            name: "ubuntu.tailnet.ts.net",
            hostname: "Ubuntu-Workstation",
            addresses: ["100.90.1.20"],
            os: "linux",
            connectedToControl: true
        )
        XCTAssertTrue(linuxNode.isLinux)
        let linuxDevice = RemoteDevice.fromTailscaleDevice(linuxNode)
        XCTAssertEqual(linuxDevice?.deviceType, .linux)
        XCTAssertEqual(linuxDevice?.remoteProtocol, .rfb)
        XCTAssertEqual(linuxDevice?.port, 5900)
    }

    func testParseLocalTailscaleCLIStatusJSON() throws {
        let localCLIJSON = """
        {
          "Version": "1.76.1",
          "Self": {
            "ID": "self_id",
            "HostName": "My-Local-Mac",
            "DNSName": "my-local-mac.tailnet.ts.net.",
            "OS": "macOS",
            "TailscaleIPs": ["100.100.1.1"],
            "Online": true
          },
          "Peer": {
            "nodekey:1111": {
              "ID": "peer_mac",
              "HostName": "Office-Mac-Studio",
              "DNSName": "office-mac-studio.tailnet.ts.net.",
              "OS": "macOS",
              "TailscaleIPs": ["100.100.1.2", "fd7a:115c::2"],
              "Online": true,
              "LastSeen": "2026-11-07T07:00:00Z"
            },
            "nodekey:2222": {
              "ID": "peer_win",
              "HostName": "Win11-Tower",
              "DNSName": "win11-tower.tailnet.ts.net.",
              "OS": "windows",
              "TailscaleIPs": ["100.100.1.3"],
              "Online": false
            },
            "nodekey:3333": {
              "ID": "peer_iphone",
              "HostName": "Chen-iPhone",
              "DNSName": "chen-iphone.tailnet.ts.net.",
              "OS": "iOS",
              "TailscaleIPs": ["100.100.1.4"],
              "Online": true
            }
          }
        }
        """

        let devices = try TailscaleClient.parseLocalStatusJSON(Data(localCLIJSON.utf8))
        // Should include macOS and Windows peers, excluding Self and mobile-only iOS peer
        XCTAssertEqual(devices.count, 2)

        let mac = try XCTUnwrap(devices.first(where: { $0.id == "peer_mac" }))
        XCTAssertEqual(mac.displayName, "Office-Mac-Studio")
        XCTAssertEqual(mac.tailscaleIPv4, "100.100.1.2")
        XCTAssertTrue(mac.isMac)
        XCTAssertTrue(mac.isOnline)

        let win = try XCTUnwrap(devices.first(where: { $0.id == "peer_win" }))
        XCTAssertEqual(win.displayName, "Win11-Tower")
        XCTAssertEqual(win.tailscaleIPv4, "100.100.1.3")
        XCTAssertTrue(win.isWindows)
        XCTAssertFalse(win.isOnline)
    }

    func testSSHConfigParserExtractsConcreteHostsAndSkipsWildcards() {
        let sampleConfig = """
        # Global defaults
        Host *
            ServerAliveInterval 60
            AddKeysToAgent yes

        Host studio-mac
            HostName 100.80.10.12
            User chenxu
            Port 2222
            IdentityFile ~/.ssh/id_ed25519

        Host prod-*
            User root

        Host jumpbox
            HostName bastion.example.com
            User ubuntu
        """

        let entries = SSHConfigParser.parse(sampleConfig)
        XCTAssertEqual(entries.count, 2)

        XCTAssertEqual(entries[0].alias, "studio-mac")
        XCTAssertEqual(entries[0].hostName, "100.80.10.12")
        XCTAssertEqual(entries[0].user, "chenxu")
        XCTAssertEqual(entries[0].port, 2222)
        XCTAssertEqual(entries[0].identityFile, "~/.ssh/id_ed25519")

        let settings0 = entries[0].toSSHConnectionSettings()
        XCTAssertNotNil(settings0)
        XCTAssertEqual(settings0?.server.host, "100.80.10.12")
        XCTAssertEqual(settings0?.server.port, 2222)
        XCTAssertEqual(settings0?.username, "chenxu")

        XCTAssertEqual(entries[1].alias, "jumpbox")
        XCTAssertEqual(entries[1].hostName, "bastion.example.com")
        XCTAssertEqual(entries[1].user, "ubuntu")
        XCTAssertEqual(entries[1].port, 22)
    }
}
