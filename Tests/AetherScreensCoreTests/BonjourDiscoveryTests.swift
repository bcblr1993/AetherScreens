import XCTest
@testable import AetherScreensCore

final class BonjourDiscoveryTests: XCTestCase {

    func testDiscoveredMacConversion() {
        let discovered = DiscoveredMac(
            name: "Chen's MacBook Pro",
            host: "Chens-MBP.local",
            port: 5900,
            isScreenSharing: true
        )

        let device = discovered.toRemoteDevice()
        XCTAssertEqual(device.name, "Chen's MacBook Pro")
        XCTAssertEqual(device.host, "Chens-MBP.local")
        XCTAssertEqual(device.port, 5900)
        XCTAssertEqual(device.deviceType, .mac)
        XCTAssertTrue(device.isOnline)
        XCTAssertFalse(device.isTailscaleNode)
    }

    func testDiscoveredMacIdentifier() {
        let d1 = DiscoveredMac(name: "Studio", host: "192.168.1.100", port: 5900)
        let d2 = DiscoveredMac(name: "Studio", host: "192.168.1.100", port: 5900)
        let d3 = DiscoveredMac(name: "Studio2", host: "192.168.1.101", port: 5900)

        XCTAssertEqual(d1.id, d2.id)
        XCTAssertNotEqual(d1.id, d3.id)
    }
}
