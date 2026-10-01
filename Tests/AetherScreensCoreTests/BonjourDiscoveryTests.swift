import XCTest
import Combine
@testable import AetherScreensCore

final class BonjourDiscoveryTests: XCTestCase {
    @MainActor
    func testLiveServiceResolvesActualHostInsteadOfDisplayName() throws {
        let env = ProcessInfo.processInfo.environment
        guard let name = env["AETHERSCREENS_BONJOUR_TEST_NAME"],
              let host = env["AETHERSCREENS_BONJOUR_TEST_HOST"] else {
            throw XCTSkip("Requires an explicitly selected LAN Bonjour service")
        }
        let discovery = BonjourDiscoveryService()
        let resolved = expectation(description: "Selected Bonjour service resolves its SRV host")
        resolved.assertForOverFulfill = false
        var device: DiscoveredMac?
        let subscription = discovery.$discoveredMacs.sink { devices in
            if let match = devices.first(where: { $0.name == name }) {
                device = match
                resolved.fulfill()
            }
        }
        defer { discovery.stopDiscovery(); subscription.cancel() }
        discovery.startDiscovery()
        wait(for: [resolved], timeout: 15)
        XCTAssertEqual(device?.host, host)
        XCTAssertEqual(device?.port, 5900)
        XCTAssertNotEqual(device?.host, "\(name).local.")
    }
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
