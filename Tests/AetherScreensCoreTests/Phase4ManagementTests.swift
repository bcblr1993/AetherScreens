import XCTest
@testable import AetherScreensCore

final class Phase4ManagementTests: XCTestCase {

    @MainActor
    func testTagAggregationAndFilteringInDeviceListViewModel() throws {
        let suiteName = "Phase4Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DeviceStore(userDefaults: defaults)
        let mac1 = RemoteDevice(
            name: "Studio Mac",
            host: "10.0.0.10",
            port: 5900,
            deviceType: .mac,
            tags: ["Work", "Design"]
        )
        let win1 = RemoteDevice(
            name: "Gaming Rig",
            host: "10.0.0.20",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            tags: ["Home", "GPU"]
        )
        let linux1 = RemoteDevice(
            name: "Build Server",
            host: "10.0.0.30",
            port: 5900,
            deviceType: .linux,
            tags: ["Work", "CI"]
        )

        store.addDevice(mac1)
        store.addDevice(win1)
        store.addDevice(linux1)

        let vm = DeviceListViewModel(store: store)
        XCTAssertEqual(vm.allTags, ["CI", "Design", "GPU", "Home", "Work"])
        XCTAssertEqual(vm.filteredDevices.count, 3)

        // Filter by tag "Work"
        vm.selectedTag = "Work"
        XCTAssertEqual(vm.filteredDevices.map(\.name), ["Studio Mac", "Build Server"])

        // Combine tag filter with search query
        vm.searchText = "Build"
        XCTAssertEqual(vm.filteredDevices.map(\.name), ["Build Server"])

        // Search by tag name when selectedTag is nil
        vm.selectedTag = nil
        vm.searchText = "GPU"
        XCTAssertEqual(vm.filteredDevices.map(\.name), ["Gaming Rig"])
    }

    func testDeviceLibraryArchiveExportAndImportPreservesExistingIdentity() throws {
        let suiteName = "Phase4ArchiveTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let existingID = UUID()
        let store = DeviceStore(userDefaults: defaults)
        let existing = RemoteDevice(
            id: existingID,
            name: "Old Name",
            host: "192.168.1.50",
            port: 5900,
            deviceType: .mac,
            tags: ["OldTag"]
        )
        store.addDevice(existing)

        // Export archive containing an updated version of 192.168.1.50:5900 and a brand new Windows PC
        let exportedDevices = [
            RemoteDevice(
                id: UUID(),
                name: "Updated Studio Mac",
                host: "192.168.1.50",
                port: 5900,
                deviceType: .mac,
                macAddress: "AA:BB:CC:DD:EE:FF",
                isFavorite: true,
                tags: ["Studio", "Prod"],
                wakeBeforeConnect: true
            ),
            RemoteDevice(
                name: "New Windows Workstation",
                host: "192.168.1.88",
                port: 3389,
                deviceType: .windows,
                remoteProtocol: .rdp,
                authMethod: .windowsCredentials,
                username: "administrator",
                desktopWidth: 2560,
                desktopHeight: 1440
            )
        ]

        let archiveData = try DeviceLibraryArchive.export(devices: exportedDevices)
        let importedCount = try store.importArchive(archiveData)
        XCTAssertEqual(importedCount, 2)
        XCTAssertEqual(store.devices.count, 2)

        // Existing host:port should keep its original UUID while updating metadata
        let mergedMac = try XCTUnwrap(store.devices.first(where: { $0.host == "192.168.1.50" }))
        XCTAssertEqual(mergedMac.id, existingID)
        XCTAssertEqual(mergedMac.name, "Updated Studio Mac")
        XCTAssertTrue(mergedMac.isFavorite)
        XCTAssertEqual(mergedMac.tags, ["Studio", "Prod"])
        XCTAssertEqual(mergedMac.wakeBeforeConnect, true)

        let addedWin = try XCTUnwrap(store.devices.first(where: { $0.host == "192.168.1.88" }))
        XCTAssertEqual(addedWin.remoteProtocol, .rdp)
        XCTAssertEqual(addedWin.port, 3389)
        XCTAssertEqual(addedWin.desktopWidth, 2560)
    }
}
