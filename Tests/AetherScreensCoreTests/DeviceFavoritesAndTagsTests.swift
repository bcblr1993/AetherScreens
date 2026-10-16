import XCTest
@testable import AetherScreensCore

@MainActor
final class DeviceFavoritesAndTagsTests: XCTestCase {
    private var testDefaults: UserDefaults!
    private var suiteName: String!
    private var testKeychain: KeychainStore!
    private var store: DeviceStore!

    override func setUp() {
        super.setUp()
        suiteName = "test.aetherscreens.favorites.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        testKeychain = KeychainStore(serviceName: suiteName, legacyServiceName: nil) { _, _, _ in true }
        store = DeviceStore(userDefaults: testDefaults, keychain: testKeychain)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        testKeychain = nil
        store = nil
        super.tearDown()
    }

    func testRemoteDeviceEncodesAndDecodesFavoriteAndTags() throws {
        let dev = RemoteDevice(
            name: "Work Mac Studio",
            host: "100.80.20.10",
            port: 5900,
            deviceType: .mac,
            isFavorite: true,
            tags: ["Office", "Production"]
        )

        let data = try JSONEncoder().encode(dev)
        let decoded = try JSONDecoder().decode(RemoteDevice.self, from: data)

        XCTAssertEqual(decoded.id, dev.id)
        XCTAssertEqual(decoded.name, "Work Mac Studio")
        XCTAssertTrue(decoded.isFavorite)
        XCTAssertEqual(decoded.tags, ["Office", "Production"])
    }

    func testRemoteDeviceBackwardsCompatibilityWithMissingFavoriteAndTags() throws {
        let legacyJSON = """
        {
            "id": "\(UUID().uuidString)",
            "name": "Legacy Mac mini",
            "host": "192.168.1.50",
            "port": 5900,
            "deviceType": "macOS",
            "remoteProtocol": "RFB",
            "authMethod": "VNC Password",
            "isOnline": true,
            "isTailscaleNode": false
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(RemoteDevice.self, from: legacyJSON)
        XCTAssertEqual(decoded.name, "Legacy Mac mini")
        XCTAssertFalse(decoded.isFavorite)
        XCTAssertEqual(decoded.tags, [])
    }

    func testDeviceListViewModelToggleFavorite() {
        let dev = RemoteDevice(name: "MacBook Air", host: "10.0.0.5", isFavorite: false)
        XCTAssertTrue(store.addDevice(dev))

        let viewModel = DeviceListViewModel(store: store)
        XCTAssertEqual(viewModel.devices.count, 1)
        XCTAssertFalse(viewModel.devices[0].isFavorite)

        viewModel.toggleFavorite(for: dev)
        XCTAssertTrue(viewModel.devices[0].isFavorite)

        // Verify persisted in store
        let reloadedStore = DeviceStore(userDefaults: testDefaults, keychain: testKeychain)
        XCTAssertTrue(reloadedStore.devices[0].isFavorite)

        // Toggle back
        viewModel.toggleFavorite(for: viewModel.devices[0])
        XCTAssertFalse(viewModel.devices[0].isFavorite)
    }

    func testDeviceListViewModelUpdateTags() {
        let dev = RemoteDevice(name: "Ubuntu Server", host: "10.0.0.8", tags: [])
        XCTAssertTrue(store.addDevice(dev))

        let viewModel = DeviceListViewModel(store: store)
        XCTAssertEqual(viewModel.devices[0].tags, [])

        viewModel.updateTags(for: dev, tags: ["Server", "Linux", "Homelab"])
        XCTAssertEqual(viewModel.devices[0].tags, ["Server", "Linux", "Homelab"])

        let reloadedStore = DeviceStore(userDefaults: testDefaults, keychain: testKeychain)
        XCTAssertEqual(reloadedStore.devices[0].tags, ["Server", "Linux", "Homelab"])
    }

    func testDeviceCategoryFavoritesFilter() {
        let favoriteDev = RemoteDevice(name: "Personal Mac", host: "10.0.0.1", isFavorite: true)
        let normalDev = RemoteDevice(name: "Test VM", host: "10.0.0.2", isFavorite: false)
        XCTAssertTrue(store.addDevice(favoriteDev))
        XCTAssertTrue(store.addDevice(normalDev))

        let viewModel = DeviceListViewModel(store: store)
        XCTAssertEqual(viewModel.devices.count, 2)

        let favorites = viewModel.devices.filter { $0.isFavorite }
        XCTAssertEqual(favorites.count, 1)
        XCTAssertEqual(favorites.first?.name, "Personal Mac")
    }
}
