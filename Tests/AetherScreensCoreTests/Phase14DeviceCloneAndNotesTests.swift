import XCTest
@testable import AetherScreensCore

final class Phase14DeviceCloneAndNotesTests: XCTestCase {

    @MainActor
    func testDuplicateDeviceAndSearchableNotes() throws {
        let suiteName = "Phase14Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DeviceStore(userDefaults: defaults)
        let original = RemoteDevice(
            name: "GPU Render Node",
            host: "10.0.50.12",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "renderadmin",
            lastConnected: Date(),
            macAddress: "11:22:33:44:55:66",
            isFavorite: true,
            tags: ["Render", "Cluster"],
            desktopWidth: 2560,
            desktopHeight: 1440,
            remoteAudioEnabled: true,
            autoFitResolution: true,
            wakeBeforeConnect: true,
            sharedDirectoryPath: "/Users/Shared/RenderOut",
            notes: "Located in Rack-42, RTX 4090 Node"
        )
        store.addDevice(original)

        let vm = DeviceListViewModel(store: store)
        // 1. Search by notes content ("Rack-42")
        vm.searchText = "Rack-42"
        XCTAssertEqual(vm.filteredDevices.map(\.id), [original.id])
        vm.searchText = ""

        // 2. Duplicate device
        let cloned = vm.duplicateDevice(original)
        XCTAssertNotEqual(cloned.id, original.id)
        XCTAssertEqual(cloned.name, "GPU Render Node Copy")
        XCTAssertEqual(cloned.host, original.host)
        XCTAssertEqual(cloned.port, original.port)
        XCTAssertEqual(cloned.deviceType, original.deviceType)
        XCTAssertEqual(cloned.remoteProtocol, original.remoteProtocol)
        XCTAssertEqual(cloned.username, original.username)
        XCTAssertEqual(cloned.tags, original.tags)
        XCTAssertEqual(cloned.desktopWidth, original.desktopWidth)
        XCTAssertEqual(cloned.desktopHeight, original.desktopHeight)
        XCTAssertEqual(cloned.sharedDirectoryPath, original.sharedDirectoryPath)
        XCTAssertEqual(cloned.notes, original.notes)
        XCTAssertNil(cloned.lastConnected)
        XCTAssertEqual(vm.devices.count, 2)

        // 3. Verify Codable & Sync Metadata for notes
        let encoded = try JSONEncoder().encode(cloned)
        let decoded = try JSONDecoder().decode(RemoteDevice.self, from: encoded)
        XCTAssertEqual(decoded.notes, "Located in Rack-42, RTX 4090 Node")

        let syncMeta = ComputerSyncMetadata(device: decoded)
        XCTAssertEqual(syncMeta.notes, "Located in Rack-42, RTX 4090 Node")
    }
}
