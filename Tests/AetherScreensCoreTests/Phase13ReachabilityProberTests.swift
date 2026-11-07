import XCTest
@testable import AetherScreensCore

final class Phase13ReachabilityProberTests: XCTestCase {

    func testProbeEndpointUsesSSHJumpServerWhenTunnelConfigured() throws {
        let directMac = RemoteDevice(name: "Direct Mac", host: "192.168.1.20", port: 5900)
        let directEndpoint = HostPortReachabilityProber.probeEndpoint(for: directMac)
        XCTAssertEqual(directEndpoint.host, "192.168.1.20")
        XCTAssertEqual(directEndpoint.port, 5900)

        let sshServer = try XCTUnwrap(SSHServerAddress(host: "bastion.example.com", port: 2222))
        let sshSettings = try XCTUnwrap(SSHConnectionSettings(server: sshServer, username: "ops", authentication: .password))
        let tunneledWin = RemoteDevice(
            name: "Tunneled Win",
            host: "10.10.0.50",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            ssh: sshSettings
        )
        let tunneledEndpoint = HostPortReachabilityProber.probeEndpoint(for: tunneledWin)
        XCTAssertEqual(tunneledEndpoint.host, "bastion.example.com")
        XCTAssertEqual(tunneledEndpoint.port, 2222)
    }

    @MainActor
    func testProbeSavedDevicesReachabilityUpdatesOnlineStatusAndLatency() async throws {
        let suiteName = "Phase13Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DeviceStore(userDefaults: defaults)
        let devOnline = RemoteDevice(name: "Fast Local Mac", host: "192.168.1.10", port: 5900, isOnline: false)
        let devOffline = RemoteDevice(name: "Sleeping PC", host: "192.168.1.99", port: 3389, deviceType: .windows, remoteProtocol: .rdp, isOnline: true)
        store.addDevice(devOnline)
        store.addDevice(devOffline)

        let vm = DeviceListViewModel(store: store)
        let prober = HostPortReachabilityProber { host, port in
            if host == "192.168.1.10" && port == 5900 {
                return .init(isReachable: true, latencyMs: 12)
            } else {
                return .init(isReachable: false, latencyMs: nil)
            }
        }

        await vm.probeSavedDevicesReachability(using: prober)

        let updatedOnline = try XCTUnwrap(vm.devices.first(where: { $0.id == devOnline.id }))
        let updatedOffline = try XCTUnwrap(vm.devices.first(where: { $0.id == devOffline.id }))
        XCTAssertTrue(updatedOnline.isOnline)
        XCTAssertEqual(vm.lastProbeLatencyMs[devOnline.id], 12)
        XCTAssertFalse(updatedOffline.isOnline)
        XCTAssertNil(vm.lastProbeLatencyMs[devOffline.id])
    }
}
