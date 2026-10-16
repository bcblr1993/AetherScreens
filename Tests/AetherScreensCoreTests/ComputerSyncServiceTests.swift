import XCTest
import Combine
@testable import AetherScreensCore

@MainActor
final class ComputerSyncServiceTests: XCTestCase {
    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testInitialStateIsDisabledByDefault() throws {
        let suite = "test.aetherscreens.sync-service.initial.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = DeviceStore(userDefaults: defaults)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let service = ComputerSyncService(store: store, userDefaults: defaults, rootDirectory: root)
        XCTAssertFalse(service.isEnabled)
        XCTAssertEqual(service.status, .disabled)
        XCTAssertNil(service.lastSyncDate)
    }

    func testEnableSyncActivatesCoordinatorAndPerformsInitialSync() async throws {
        let suite = "test.aetherscreens.sync-service.enable.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = DeviceStore(userDefaults: defaults)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let localDevice = RemoteDevice(name: "Mac Studio", host: "studio.local")
        store.addDevice(localDevice)

        var remoteJournal = ComputerSyncJournal()
        let remoteDevice = RemoteDevice(name: "MacBook Pro", host: "mbp.local")
        try remoteJournal.upsert(ComputerSyncMetadata(device: remoteDevice))
        let transport = TestSyncTransport(account: "test-user-record", initialSnapshot: try remoteJournal.encoded())

        let service = ComputerSyncService(
            store: store,
            userDefaults: defaults,
            rootDirectory: root,
            transportFactory: { (transport, "test-user-record") }
        )

        let statusExpectation = expectation(description: "Status transitions to synced")
        service.$status
            .dropFirst()
            .sink { status in
                if case .synced = status {
                    statusExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        await service.setEnabled(true)

        await fulfillment(of: [statusExpectation], timeout: 5)
        XCTAssertTrue(service.isEnabled)
        XCTAssertNotNil(service.lastSyncDate)

        // Remote device should be merged into store
        let currentDevices = store.devices
        XCTAssertEqual(Set(currentDevices.map(\.name)), Set(["Mac Studio", "MacBook Pro"]))
    }

    func testSyncFailureUpdatesStatusWithErrorAndKeepsLocalDevices() async throws {
        let suite = "test.aetherscreens.sync-service.failure.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = DeviceStore(userDefaults: defaults)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let localDevice = RemoteDevice(name: "Local Only", host: "local.invalid")
        store.addDevice(localDevice)

        struct FailingTransport: ComputerSyncTransport {
            func fetch() async throws -> CloudKitComputerSyncReader.Read {
                throw CloudKitComputerSyncReader.Failure.accountUnavailable
            }
            func save(journal: Data, accountIdentifier: String, expectedChangeTag: String?) async throws -> CloudKitComputerSyncReader.Read {
                throw CloudKitComputerSyncReader.Failure.accountUnavailable
            }
        }

        let service = ComputerSyncService(
            store: store,
            userDefaults: defaults,
            rootDirectory: root,
            transportFactory: { (FailingTransport(), "test-account") }
        )

        await service.setEnabled(true)

        if case .error(let msg) = service.status {
            XCTAssertFalse(msg.isEmpty)
        } else {
            XCTFail("Status should be in error state, got: \(service.status)")
        }

        // Local device must be preserved
        XCTAssertEqual(store.devices.map(\.name), ["Local Only"])
    }

    func testDisableSyncClearsActiveCoordinatorAndSetsDisabledStatus() async throws {
        let suite = "test.aetherscreens.sync-service.disable.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = DeviceStore(userDefaults: defaults)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let transport = TestSyncTransport(account: "test-user-record", initialSnapshot: try ComputerSyncJournal().encoded())
        let service = ComputerSyncService(
            store: store,
            userDefaults: defaults,
            rootDirectory: root,
            transportFactory: { (transport, "test-user-record") }
        )

        await service.setEnabled(true)
        XCTAssertTrue(service.isEnabled)

        await service.setEnabled(false)
        XCTAssertFalse(service.isEnabled)
        XCTAssertEqual(service.status, .disabled)
    }

    func testDeviceListViewModelIntegratesSyncService() async throws {
        let suite = "test.aetherscreens.viewmodel.sync.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = DeviceStore(userDefaults: defaults)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        var remoteJournal = ComputerSyncJournal()
        let remoteDevice = RemoteDevice(name: "Remote Mac", host: "remote.local")
        try remoteJournal.upsert(ComputerSyncMetadata(device: remoteDevice))
        let transport = TestSyncTransport(account: "account-vm", initialSnapshot: try remoteJournal.encoded())

        let syncService = ComputerSyncService(
            store: store,
            userDefaults: defaults,
            rootDirectory: root,
            transportFactory: { (transport, "account-vm") }
        )

        let viewModel = DeviceListViewModel(store: store, syncService: syncService)
        XCTAssertEqual(viewModel.devices.count, 0)

        // Turn on sync via ViewModel
        await viewModel.syncService.setEnabled(true)

        // ViewModel devices should be refreshed
        XCTAssertTrue(viewModel.devices.contains(where: { $0.name == "Remote Mac" }))
    }
}

private actor TestSyncTransport: ComputerSyncTransport {
    let account: String
    var currentJournal: Data
    var changeTag: String = "v1"

    init(account: String, initialSnapshot: Data) {
        self.account = account
        self.currentJournal = initialSnapshot
    }

    func fetch() async throws -> CloudKitComputerSyncReader.Read {
        .init(accountIdentifier: account, snapshot: .init(journal: currentJournal, changeTag: changeTag))
    }

    func save(journal: Data, accountIdentifier: String, expectedChangeTag: String?) async throws -> CloudKitComputerSyncReader.Read {
        currentJournal = journal
        changeTag = UUID().uuidString
        return .init(accountIdentifier: account, snapshot: .init(journal: journal, changeTag: changeTag))
    }
}
