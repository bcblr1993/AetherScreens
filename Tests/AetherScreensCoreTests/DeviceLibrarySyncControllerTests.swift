import XCTest
import Combine
import CloudKit
@testable import AetherScreensCore

final class DeviceLibrarySyncControllerTests: XCTestCase {
    private var suites: [String] = []

    override func tearDown() {
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        suites = []; super.tearDown()
    }

    private func library() throws -> (DeviceStore, UserDefaults) {
        let suite = "test.aetherscreens.sync.controller." + UUID().uuidString
        suites.append(suite)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (TestStorage.make(userDefaults: defaults), defaults)
    }

    private func remoteDocument(_ devices: [RemoteDevice]) throws -> (Data, UUID) {
        let replica = UUID()
        var document = DeviceSyncDocument(replicaID: replica)
        try document.recordLocalDevices(devices)
        return (try document.encoded(), replica)
    }

    @MainActor
    private func waitForStatus(_ expected: DeviceLibrarySyncStatus,
                               _ controller: DeviceLibrarySyncController) async throws {
        for _ in 0..<100 {
            if controller.status == expected { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Expected synchronization state was not reached")
    }

    @MainActor
    func testLocalStorageNeverCreatesTransportOrContactsAccount() async throws {
        let (store, _) = try library()
        let transport = SyncTestTransport()
        let controller = DeviceLibrarySyncController(store: store, transportFactory: { transport })
        controller.resumeAutomaticSynchronization()
        await controller.synchronizeNow()
        XCTAssertEqual(controller.storageMode, .local)
        XCTAssertEqual(controller.status, .local)
        let counts = await transport.counts()
        XCTAssertEqual(counts.fetch, 0); XCTAssertEqual(counts.publish, 0)
    }

    @MainActor
    func testUnconfiguredCloudChoicePreservesLibraryAndCanReturnToLocal() async throws {
        let (store, defaults) = try library()
        let computer = RemoteDevice(name: "Offline QA", host: "qa.invalid")
        store.addDevice(computer)
        let controller = DeviceLibrarySyncController(store: store)
        controller.selectStorage(.iCloud)
        await controller.synchronizeNow()
        XCTAssertEqual(controller.status, .failed(.notConfigured))
        XCTAssertEqual(store.devicesSnapshot(), [computer])
        let restarted = TestStorage.make(userDefaults: defaults)
        XCTAssertEqual(restarted.storageMode, .iCloud)
        XCTAssertEqual(restarted.devicesSnapshot(), [computer])
        controller.selectStorage(.local)
        XCTAssertEqual(controller.status, .local)
        XCTAssertEqual(controller.storageMode, .local)
        XCTAssertEqual(TestStorage.make(userDefaults: defaults).storageMode, .local)
    }

    @MainActor
    func testRemoteImportPublishesOnceWithoutNotificationFeedbackLoop() async throws {
        let (store, _) = try library()
        let transport = SyncTestTransport()
        let computer = RemoteDevice(name: "Imported QA", host: "qa.invalid")
        let (data, id) = try remoteDocument([computer])
        await transport.seed(data, for: id)
        let controller = DeviceLibrarySyncController(store: store, transportFactory: { transport },
                                                     debounceNanoseconds: 10_000_000)
        controller.selectStorage(.iCloud)
        controller.resumeAutomaticSynchronization()
        try await waitForStatus(.synchronized, controller)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(store.devicesSnapshot().map(\.id), [computer.id])
        let counts = await transport.counts()
        XCTAssertEqual(counts.fetch, 1); XCTAssertEqual(counts.publish, 1)
        controller.suspendAutomaticSynchronization()
    }

    @MainActor
    func testForegroundPreferenceChangesAreDebouncedAndRuntimeHistoryDoesNotUpload() async throws {
        let (store, _) = try library()
        let computer = RemoteDevice(name: "Preferences QA", host: "qa.invalid")
        store.addDevice(computer)
        let transport = SyncTestTransport()
        let controller = DeviceLibrarySyncController(store: store, transportFactory: { transport },
                                                     debounceNanoseconds: 30_000_000)
        controller.selectStorage(.iCloud)
        controller.resumeAutomaticSynchronization()
        await controller.synchronizeNow()
        for speed in [1.25, 1.5, 1.75] { store.updateCursorSpeed(speed, for: computer) }
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(controller.status, .synchronized)
        let first = await transport.counts()
        XCTAssertEqual(first.publish, 2)
        let replica = try store.synchronizationReplica()
        let uploadedData = await transport.uploaded(for: replica.replicaID)
        let uploaded = try XCTUnwrap(uploadedData)
        let document = try DeviceSyncDocument(data: uploaded, replicaID: replica.replicaID)
        XCTAssertEqual(document.devices().first?.effectiveCursorSpeed, 1.75)
        store.recordConnection(for: computer)
        try await Task.sleep(nanoseconds: 100_000_000)
        let afterRuntime = await transport.counts()
        XCTAssertEqual(afterRuntime.publish, 2)
        controller.suspendAutomaticSynchronization()
    }

    @MainActor
    func testSwitchingToLocalCancelsActiveFetchAndCannotPublishOrOverwriteState() async throws {
        let (store, _) = try library()
        let transport = SyncTestTransport()
        let started = expectation(description: "Actual exchange started fetching")
        await transport.configure(fetchDelay: true, fetchStarted: { started.fulfill() })
        let controller = DeviceLibrarySyncController(store: store, transportFactory: { transport })
        controller.selectStorage(.iCloud)
        let running = Task { await controller.synchronizeNow() }
        await fulfillment(of: [started], timeout: 2)
        controller.selectStorage(.local)
        await running.value
        XCTAssertEqual(controller.status, .local)
        let counts = await transport.counts()
        XCTAssertEqual(counts.fetch, 1); XCTAssertEqual(counts.publish, 0)
    }

    @MainActor
    func testAccountNotificationCancelsOldExchangeAndNeverRebindsSavedData() async throws {
        let (store, defaults) = try library()
        let transport = SyncTestTransport()
        let started = expectation(description: "Account A fetch started")
        await transport.configure(fetchDelay: true, fetchStarted: { started.fulfill() })
        let controller = DeviceLibrarySyncController(store: store, transportFactory: { transport })
        controller.selectStorage(.iCloud)
        let running = Task { await controller.synchronizeNow() }
        await fulfillment(of: [started], timeout: 2)
        await transport.configure(account: "test-account-B")
        NotificationCenter.default.post(name: .CKAccountChanged, object: nil)
        try await waitForStatus(.pending, controller)
        await running.value
        await controller.synchronizeNow()
        XCTAssertEqual(controller.status, .failed(.accountChanged))
        XCTAssertEqual(defaults.string(forKey: "com.aethernative.aetherscreens.sync.bound-account.v1"), "test-account-A")
        let counts = await transport.counts()
        XCTAssertEqual(counts.fetch, 1); XCTAssertEqual(counts.publish, 0)
    }

    @MainActor
    func testUploadFailureCanRetryWithoutLosingImportedComputer() async throws {
        let (store, defaults) = try library()
        let transport = SyncTestTransport()
        let computer = RemoteDevice(name: "Retry QA", host: "qa.invalid")
        let (data, id) = try remoteDocument([computer])
        await transport.seed(data, for: id)
        await transport.configure(publishFailure: .remoteConflict)
        let controller = DeviceLibrarySyncController(store: store, transportFactory: { transport })
        controller.selectStorage(.iCloud)
        await controller.synchronizeNow()
        XCTAssertEqual(controller.status, .failed(.conflict))
        XCTAssertEqual(store.devicesSnapshot().map(\.id), [computer.id])
        XCTAssertEqual(TestStorage.make(userDefaults: defaults).devicesSnapshot().map(\.id), [computer.id])
        await transport.configure()
        await controller.synchronizeNow()
        XCTAssertEqual(controller.status, .synchronized)
        XCTAssertEqual(store.devicesSnapshot().map(\.id), [computer.id])
    }

    @MainActor
    func testLocalEditsDuringPublishRemainPendingThenRetryUploadsThem() async throws {
        let (store, _) = try library()
        let computer = RemoteDevice(name: "In Flight QA", host: "qa.invalid")
        store.addDevice(computer)
        let transport = SyncTestTransport()
        await transport.configure(onPublish: { store.updateCursorSpeed(1.75, for: computer) })
        let controller = DeviceLibrarySyncController(store: store, transportFactory: { transport })
        controller.selectStorage(.iCloud)
        await controller.synchronizeNow()
        XCTAssertEqual(controller.status, .pending)
        await transport.configure()
        await controller.synchronizeNow()
        XCTAssertEqual(controller.status, .synchronized)
        let counts = await transport.counts()
        XCTAssertEqual(counts.publish, 2)
    }

    @MainActor
    func testSuspendingForegroundSynchronizationCancelsFetchAndResumesOnce() async throws {
        let (store, _) = try library()
        let transport = SyncTestTransport()
        let started = expectation(description: "Foreground fetch started")
        await transport.configure(fetchDelay: true, fetchStarted: { started.fulfill() })
        let controller = DeviceLibrarySyncController(store: store, transportFactory: { transport },
                                                     debounceNanoseconds: 10_000_000)
        controller.selectStorage(.iCloud)
        controller.resumeAutomaticSynchronization()
        await fulfillment(of: [started], timeout: 2)
        controller.suspendAutomaticSynchronization()
        XCTAssertEqual(controller.status, .pending)
        await transport.configure()
        controller.resumeAutomaticSynchronization()
        try await waitForStatus(.synchronized, controller)
        let counts = await transport.counts()
        XCTAssertEqual(counts.fetch, 2); XCTAssertEqual(counts.publish, 1)
        controller.suspendAutomaticSynchronization()
    }

    @MainActor
    func testOtherLibraryNotificationsCannotScheduleThisController() async throws {
        let (store, _) = try library()
        let (other, _) = try library()
        let transport = SyncTestTransport()
        let controller = DeviceLibrarySyncController(store: store, transportFactory: { transport },
                                                     debounceNanoseconds: 10_000_000)
        controller.selectStorage(.iCloud)
        controller.resumeAutomaticSynchronization()
        await controller.synchronizeNow()
        other.addDevice(RemoteDevice(name: "Unrelated QA", host: "other.invalid"))
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(controller.status, .synchronized)
        let counts = await transport.counts()
        XCTAssertEqual(counts.publish, 1)
        controller.suspendAutomaticSynchronization()
    }

    func testErrorsExposeOnlyTypedLocalizedMessages() {
        let error = NSError(domain: "Synthetic QA", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Private synthetic account detail"])
        XCTAssertEqual(DeviceLibrarySyncIssue.classify(error), .network)
        XCTAssertFalse(DeviceLibrarySyncIssue.classify(error).messageKey.contains("Private"))
        XCTAssertEqual(DeviceLibrarySyncIssue.classify(DeviceSyncDocument.Failure.quotaExceeded), .quota)
        XCTAssertEqual(DeviceLibrarySyncIssue.classify(CKError(.notAuthenticated)), .accountUnavailable)
        XCTAssertEqual(DeviceLibrarySyncIssue.classify(CKError(.missingEntitlement)), .notConfigured)
    }

    @MainActor
    func testRejectedCloudQuotaChoiceKeepsLocalComputersAndReportsFailure() async throws {
        let (store, defaults) = try library()
        let computers = (0...1024).map { RemoteDevice(name: "Local QA \($0)", host: "qa.invalid") }
        defaults.set(try JSONEncoder().encode(computers), forKey: DeviceStore.storageKey)
        store.loadDevices()
        let controller = DeviceLibrarySyncController(store: store)
        controller.selectStorage(.iCloud)
        XCTAssertEqual(controller.storageMode, .local)
        XCTAssertEqual(controller.status, .failed(.quota))
        XCTAssertEqual(store.devicesSnapshot(), computers)
        XCTAssertEqual(TestStorage.make(userDefaults: defaults).devicesSnapshot(), computers)
    }

    @MainActor
    func testInvalidCheckpointChoiceKeepsLocalModeAndReportsPreservedData() async throws {
        let (store, defaults) = try library()
        let computer = RemoteDevice(name: "Preserved QA", host: "qa.invalid")
        store.addDevice(computer)
        let malformed = Data("Invalid synthetic checkpoint".utf8)
        defaults.set(malformed, forKey: DeviceLibrarySyncCheckpoint.key)
        store.loadDevices()
        let controller = DeviceLibrarySyncController(store: store)
        controller.selectStorage(.iCloud)
        XCTAssertEqual(controller.storageMode, .local)
        XCTAssertEqual(controller.status, .failed(.invalidData))
        XCTAssertEqual(store.devicesSnapshot(), [computer])
        XCTAssertEqual(defaults.data(forKey: DeviceLibrarySyncCheckpoint.key), malformed)
    }
}
