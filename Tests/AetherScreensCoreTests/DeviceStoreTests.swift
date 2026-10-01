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

    @MainActor
    func testTemporarySessionDoesNotCacheDesktopThumbnail() {
        let device = RemoteDevice(name: "Temporary thumbnail QA", host: "qa.invalid")
        let session = SessionViewModel(device: device, password: nil, isTemporary: true, deviceStore: makeStore())
        session.client.framebuffer.resize(newWidth: 2, newHeight: 2)
        for _ in 0..<61 { session.client.onFrameUpdated?() }
        let drained = expectation(description: "Allow any asynchronous thumbnail write to finish")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertTrue(session.hasReceivedFirstFrame, "Incoming frame callbacks must have run")
        session.endSession()
        XCTAssertNil(ThumbnailStore.shared.getThumbnail(for: device.id), "A temporary desktop must not become a persistent preview")
    }

    @MainActor
    func testTemporarySessionDoesNotPersistDeviceOrRetriedPassword() throws {
        let store = makeStore()
        let discovery = BonjourDiscoveryService()
        defer { discovery.stopDiscovery() }
        let vm = DeviceListViewModel(store: store, bonjourService: discovery)
        let request = try XCTUnwrap(ConnectionRequest(host: "qa.invalid", password: "temporary-only"))
        let session = vm.prepareQuickSession(request, saveComputer: false)
        XCTAssertTrue(session.isTemporary)
        XCTAssertFalse(session.canRememberPassword)
        session.submitPassword("retry-only", rememberInKeychain: true)
        XCTAssertEqual(session.client.password, "retry-only", "Retry must update the active client, not only Keychain")
        XCTAssertTrue(store.devices.isEmpty)
        XCTAssertNil(tempDefaults.data(forKey: DeviceStore.storageKey))
        XCTAssertNil(store.getPassword(for: request.device), "Temporary retry must not create an orphan credential")
    }

    @MainActor
    func testSavedQuickSessionPersistsDeviceAndAllowsPasswordRetry() throws {
        let store = makeStore()
        let discovery = BonjourDiscoveryService()
        defer { discovery.stopDiscovery() }
        let vm = DeviceListViewModel(store: store, bonjourService: discovery)
        let request = try XCTUnwrap(ConnectionRequest(host: "qa.invalid", username: "qa-user", password: "initial-only"))
        defer { store.deleteDevice(request.device) }
        let session = vm.prepareQuickSession(request, saveComputer: true)
        XCTAssertTrue(session.canRememberPassword)
        XCTAssertFalse(session.isTemporary)
        XCTAssertEqual(store.devices.first?.id, request.device.id)
        XCTAssertNil(store.devices.first?.lastConnected)
        XCTAssertEqual(store.getPassword(for: request.device), "initial-only")
        session.submitPassword("retry-only", rememberInKeychain: true)
        XCTAssertEqual(store.getPassword(for: request.device), "retry-only")
    }

    @MainActor
    func testConnectionAttemptDoesNotRecordSuccess() {
        let store = makeStore()
        let device = RemoteDevice(name: "Unverified Mac", host: "invalid.example")
        store.addDevice(device)
        let discovery = BonjourDiscoveryService()
        defer { discovery.stopDiscovery() }
        let viewModel = DeviceListViewModel(store: store, bonjourService: discovery)
        viewModel.connect(to: device)
        XCTAssertEqual(viewModel.activeSessionDevice?.id, device.id)
        XCTAssertNil(store.devices.first?.lastConnected, "Opening a session is not a successful connection")
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
