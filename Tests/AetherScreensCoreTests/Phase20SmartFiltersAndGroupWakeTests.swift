import XCTest
@testable import AetherScreensCore

@MainActor
final class Phase20SmartFiltersAndGroupWakeTests: XCTestCase {

    private func makeIsolatedEnvironment() -> (UserDefaults, DeviceStore, DeviceListViewModel) {
        let suiteName = "Phase20Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = DeviceStore(userDefaults: defaults)
        let vm = DeviceListViewModel(store: store, userDefaults: defaults)
        return (defaults, store, vm)
    }

    func testSmartFiltersMatchOnlineSSHTailscaleAndRecentlyConnected() throws {
        let (_, store, vm) = makeIsolatedEnvironment()
        let sshServer = try XCTUnwrap(SSHServerAddress(host: "bastion.example.com", port: 22))
        let sshSettings = try XCTUnwrap(SSHConnectionSettings(
            server: sshServer,
            username: "ops",
            authentication: .password
        ))
        let recentDate = Date().addingTimeInterval(-3600)
        let oldDate = Date().addingTimeInterval(-10 * 86_400)

        let d1 = RemoteDevice(name: "Online SSH Mac", host: "10.0.0.1", isOnline: true, lastConnected: recentDate, ssh: sshSettings)
        let d2 = RemoteDevice(name: "Offline Tailscale Win", host: "100.64.0.2", remoteProtocol: .rdp, isOnline: false, lastConnected: oldDate, isTailscaleNode: true)
        let d3 = RemoteDevice(name: "Online Local Linux", host: "10.0.0.3", deviceType: .linux, isOnline: true, lastConnected: nil)

        _ = store.addDevice(d1)
        _ = store.addDevice(d2)
        _ = store.addDevice(d3)
        vm.reload()

        vm.smartFilter = .onlineOnly
        XCTAssertEqual(vm.filteredDevices.map(\.name), ["Online SSH Mac", "Online Local Linux"])

        vm.smartFilter = .sshTunneled
        XCTAssertEqual(vm.filteredDevices.map(\.name), ["Online SSH Mac"])

        vm.smartFilter = .tailscale
        XCTAssertEqual(vm.filteredDevices.map(\.name), ["Offline Tailscale Win"])

        vm.smartFilter = .recentlyConnected
        XCTAssertEqual(vm.filteredDevices.map(\.name), ["Online SSH Mac"])

        vm.smartFilter = .all
        XCTAssertEqual(vm.filteredDevices.count, 3)
    }

    func testBatchTagAssignmentRemovalAndWakeableDeviceFiltering() {
        let (_, store, vm) = makeIsolatedEnvironment()
        let d1 = RemoteDevice(name: "Node 1", host: "10.0.1.1", macAddress: "AA:BB:CC:DD:EE:01", tags: ["Lab"])
        let d2 = RemoteDevice(name: "Node 2", host: "10.0.1.2", macAddress: "AA:BB:CC:DD:EE:02", tags: [])
        let d3 = RemoteDevice(name: "Node 3", host: "10.0.1.3", macAddress: nil, tags: ["Lab"])
        _ = store.addDevice(d1)
        _ = store.addDevice(d2)
        _ = store.addDevice(d3)
        vm.reload()

        let added = vm.assignTag("Cluster", toDeviceIDs: [d1.id, d2.id])
        XCTAssertEqual(added, 2)
        XCTAssertTrue(vm.devices.first(where: { $0.id == d1.id })?.tags.contains("Cluster") == true)
        XCTAssertTrue(vm.devices.first(where: { $0.id == d2.id })?.tags.contains("Cluster") == true)

        let wakeableCluster = vm.wakeableDevices(matchingTag: "Cluster")
        XCTAssertEqual(wakeableCluster.count, 2)

        let wakeableLab = vm.wakeableDevices(matchingTag: "Lab")
        XCTAssertEqual(wakeableLab.map(\.name), ["Node 1"])

        let removed = vm.removeTag("Cluster", fromDeviceIDs: [d1.id])
        XCTAssertEqual(removed, 1)
        XCTAssertFalse(vm.devices.first(where: { $0.id == d1.id })?.tags.contains("Cluster") == true)
    }
}
