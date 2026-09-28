import XCTest
@testable import AetherScreensCore

final class DeviceStoreTests: XCTestCase {

    var tempDefaults: UserDefaults!
    var suiteName: String!
    var keychain: KeychainStore!
    var legacyKeychain: KeychainStore!
    var legacyServiceName: String!
    var currentServiceName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.aetherscreens.\(UUID().uuidString)"
        tempDefaults = UserDefaults(suiteName: suiteName)!
        legacyServiceName = "test.aetherscreens.legacy.\(UUID().uuidString)"
        currentServiceName = "test.aetherscreens.credentials.\(UUID().uuidString)"
        keychain = KeychainStore(serviceName: currentServiceName,
                                 legacyServiceName: legacyServiceName)
        legacyKeychain = KeychainStore(serviceName: legacyServiceName, legacyServiceName: nil)
    }

    override func tearDown() {
        tempDefaults.removePersistentDomain(forName: suiteName)
        tempDefaults = nil
        keychain = nil
        legacyKeychain = nil
        super.tearDown()
    }

    private func makeStore(legacySources: [UserDefaults] = []) -> DeviceStore {
        DeviceStore(userDefaults: tempDefaults, legacySources: legacySources, keychain: keychain)
    }

    func testAddAndRetrieveDevice() {
        let store = makeStore()
        let device = RemoteDevice(
            name: "Living Room Mac",
            host: "100.80.1.20",
            port: 5900,
            deviceType: .mac
        )

        store.addDevice(device, password: "testPassword123")
        XCTAssertEqual(store.devices.count, 1)
        XCTAssertEqual(store.devices.first?.name, "Living Room Mac")

        // Password retrieval
        let retrievedPwd = store.getPassword(for: device)
        XCTAssertEqual(retrievedPwd, "testPassword123")
        store.deleteDevice(device)
    }

    func testDeleteDevice() {
        let store = makeStore()
        let device = RemoteDevice(name: "Test Mac", host: "100.80.1.30")
        store.addDevice(device, password: "secret")
        XCTAssertEqual(store.devices.count, 1)

        store.deleteDevice(device)
        XCTAssertEqual(store.devices.count, 0)
    }

    func testMergeTailscaleNodes() {
        let store = makeStore()

        let initialDevice = RemoteDevice(
            name: "My Work Mac",
            host: "100.80.10.5",
            isOnline: false
        )
        store.addDevice(initialDevice, password: "preservedPassword")

        // Tailscale returns updated status for the same IP
        let tsNode = TailscaleDevice(
            id: "node_abc",
            name: "work-mac.ts.net",
            hostname: "Work Mac Updated",
            addresses: ["100.80.10.5"],
            os: "macOS",
            connectedToControl: true
        )

        store.mergeTailscaleDevices([tsNode])

        XCTAssertEqual(store.devices.count, 1)
        XCTAssertEqual(store.devices.first?.name, "Work Mac Updated")
        XCTAssertTrue(store.devices.first?.isOnline ?? false)

        // Password should still be preserved
        let pwd = store.getPassword(for: store.devices.first!)
        XCTAssertEqual(pwd, "preservedPassword")
        store.deleteDevice(store.devices.first!)
    }

    func testMigratesLegacyDeviceListOnce() throws {
        let legacySuite = "test.aetherscreens.legacy-defaults.\(UUID().uuidString)"
        let legacyDefaults = UserDefaults(suiteName: legacySuite)!
        defer { legacyDefaults.removePersistentDomain(forName: legacySuite) }

        let legacyDevice = RemoteDevice(name: "Old Mac", host: "100.80.1.40")
        legacyDefaults.set(try JSONEncoder().encode([legacyDevice]), forKey: DeviceStore.legacyStorageKey)

        let store = makeStore(legacySources: [legacyDefaults])
        XCTAssertEqual(store.devices.map(\.id), [legacyDevice.id])
        XCTAssertNotNil(tempDefaults.data(forKey: DeviceStore.storageKey))
        // Legacy data stays for any old build still installed
        XCTAssertNotNil(legacyDefaults.data(forKey: DeviceStore.legacyStorageKey))

        // Once the current key exists, legacy data is not read again
        store.deleteDevice(legacyDevice)
        XCTAssertTrue(makeStore(legacySources: [legacyDefaults]).devices.isEmpty)
    }

    func testMigratesLegacyKeychainPasswordOnRead() {
        let device = RemoteDevice(name: "Old Mac", host: "100.80.1.41")
        let key = device.id.uuidString
        XCTAssertTrue(legacyKeychain.savePassword("legacySecret", forKey: key))

        let store = makeStore()
        XCTAssertEqual(store.getPassword(for: device), "legacySecret")

        // Moved to the current service and removed from the legacy one
        let legacyReader = KeychainStore(serviceName: legacyServiceName, legacyServiceName: nil)
        XCTAssertNil(legacyReader.loadPassword(forKey: key))
        let currentReader = KeychainStore(serviceName: currentServiceName, legacyServiceName: nil)
        XCTAssertEqual(currentReader.loadPassword(forKey: key), "legacySecret")

        store.deleteDevice(device)
    }
}
