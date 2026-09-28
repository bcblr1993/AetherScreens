import XCTest
@testable import AetherScreensCore

final class TailscaleModelsTests: XCTestCase {

    let sampleJSON = """
    {
      "devices": [
        {
          "id": "node_12345",
          "name": "macbook-pro.tailnet-xyz.ts.net",
          "hostname": "Chen-MacBook-Pro",
          "addresses": [
            "100.85.120.45",
            "fd7a:115c:a1e0:ab12:4843:cd96:6255:782d"
          ],
          "os": "macOS",
          "user": "user@example.com",
          "authorized": true,
          "connectedToControl": true,
          "lastSeen": "2026-09-23T15:30:00Z"
        },
        {
          "id": "node_67890",
          "name": "windows-workstation.tailnet-xyz.ts.net",
          "hostname": "WinDesktop",
          "addresses": [
            "100.85.120.99"
          ],
          "os": "windows",
          "authorized": true,
          "connectedToControl": false
        }
      ]
    }
    """

    func testTailscaleJSONDecoding() throws {
        let data = Data(sampleJSON.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(TailscaleDevicesResponse.self, from: data)

        XCTAssertEqual(response.devices.count, 2)

        let mac = response.devices[0]
        XCTAssertEqual(mac.id, "node_12345")
        XCTAssertEqual(mac.displayName, "Chen-MacBook-Pro")
        XCTAssertEqual(mac.tailscaleIPv4, "100.85.120.45")
        XCTAssertTrue(mac.isMac)
        XCTAssertTrue(mac.isOnline)

        let win = response.devices[1]
        XCTAssertEqual(win.displayName, "WinDesktop")
        XCTAssertEqual(win.tailscaleIPv4, "100.85.120.99")
        XCTAssertFalse(win.isMac)
        XCTAssertFalse(win.isOnline)
    }

    func testConversionToRemoteDevice() throws {
        let ts = TailscaleDevice(
            id: "node_999",
            name: "imac.ts.net",
            hostname: "Studio-iMac",
            addresses: ["100.64.1.2"],
            os: "macOS",
            connectedToControl: true
        )

        let remote = RemoteDevice.fromTailscaleDevice(ts)
        XCTAssertNotNil(remote)
        XCTAssertEqual(remote?.name, "Studio-iMac")
        XCTAssertEqual(remote?.host, "100.64.1.2")
        XCTAssertEqual(remote?.port, 5900)
        XCTAssertEqual(remote?.deviceType, .mac)
        XCTAssertTrue(remote?.isOnline ?? false)
        XCTAssertTrue(remote?.isTailscaleNode ?? false)
    }
}
