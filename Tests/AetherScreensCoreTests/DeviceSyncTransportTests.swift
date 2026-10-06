import XCTest
import CloudKit
@testable import AetherScreensCore

actor SyncTestTransport: DeviceSyncTransport {
    var account = "test-account-A"
    var records: [UUID: (data: Data, revision: Int)] = [:]
    var fetchFailure: DeviceSyncFailure?
    var publishFailure: DeviceSyncFailure?
    var nextAccountAfterFetch: String?
    var fetchStarted: (@Sendable () -> Void)?
    var accountStarted: (@Sendable () -> Void)?
    var fetchDelay = false
    var staleOwnVersion = false
    var onPublish: (@Sendable () throws -> Void)?
    var fetchCount = 0
    var publishCount = 0

    func accountIdentifier() async throws -> String {
        accountStarted?()
        return account
    }

    func fetchDocuments(replicaID: UUID, account: String) async throws -> DeviceSyncRemoteSnapshot {
        guard account == self.account else { throw DeviceSyncFailure.accountChanged }
        fetchCount += 1
        fetchStarted?()
        if fetchDelay { try await Task.sleep(nanoseconds: 10_000_000_000) }
        if let fetchFailure { throw fetchFailure }
        let version = records[replicaID].map { Data(String($0.revision).utf8) }
        let documents = records.values.map(\.data)
        if staleOwnVersion, let current = records[replicaID] {
            records[replicaID] = (current.data, current.revision + 1)
        }
        if let nextAccountAfterFetch { self.account = nextAccountAfterFetch }
        return .init(documents: documents, localReplicaVersion: version)
    }

    func publish(_ document: Data, replicaID: UUID, account: String, version: Data?) async throws {
        guard account == self.account else { throw DeviceSyncFailure.accountChanged }
        if let publishFailure { throw publishFailure }
        let current = records[replicaID].map { Data(String($0.revision).utf8) }
        guard version == current else { throw DeviceSyncFailure.remoteConflict }
        publishCount += 1
        records[replicaID] = (document, (records[replicaID]?.revision ?? 0) + 1)
        try onPublish?()
    }

    func configure(account: String? = nil, fetchFailure: DeviceSyncFailure? = nil,
                   publishFailure: DeviceSyncFailure? = nil, accountAfterFetch: String? = nil,
                   staleOwnVersion: Bool = false, fetchDelay: Bool = false,
                   fetchStarted: (@Sendable () -> Void)? = nil,
                   accountStarted: (@Sendable () -> Void)? = nil,
                   onPublish: (@Sendable () throws -> Void)? = nil) {
        if let account { self.account = account }
        self.fetchFailure = fetchFailure; self.publishFailure = publishFailure
        nextAccountAfterFetch = accountAfterFetch; self.staleOwnVersion = staleOwnVersion
        self.fetchDelay = fetchDelay; self.fetchStarted = fetchStarted; self.onPublish = onPublish
        self.accountStarted = accountStarted
    }

    func seed(_ data: Data, for id: UUID) { records[id] = (data, 1) }
    func counts() -> (fetch: Int, publish: Int) { (fetchCount, publishCount) }
    func uploaded(for id: UUID) -> Data? { records[id]?.data }
}

final class DeviceSyncTransportTests: XCTestCase {
    private var suites: [String] = []

    override func tearDown() {
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        suites = []; super.tearDown()
    }

    private func makeStore() throws -> (DeviceSyncStore, UserDefaults) {
        let suite = "test.aetherscreens.sync.exchange.\(UUID().uuidString)"
        suites.append(suite)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (try DeviceSyncStore(defaults: defaults), defaults)
    }

    private func device() -> RemoteDevice { RemoteDevice(name: "Sync QA", host: "qa.invalid") }

    func testTwoReplicasKeepSeparateCloudRecordsAndMergeOfflinePreferences() async throws {
        let transport = SyncTestTransport()
        let (a, da) = try makeStore(); let (b, db) = try makeStore()
        let ea = DeviceSyncExchange(store: a, transport: transport, defaults: da)
        let eb = DeviceSyncExchange(store: b, transport: transport, defaults: db)
        let original = device()
        let first = try await ea.synchronize(localDevices: [original])
        XCTAssertEqual(first, .synchronized)
        try b.receive(a.exportedData())
        var right = try XCTUnwrap(b.devices().first); right.cursorSpeed = 1.75
        let second = try await eb.synchronize(localDevices: [right])
        XCTAssertEqual(second, .synchronized)
        var left = try XCTUnwrap(a.devices().first); left.name = "Offline name on A"
        _ = try await ea.synchronize(localDevices: [left])
        _ = try await eb.synchronize(localDevices: b.devices())
        XCTAssertEqual(try a.exportedData(), try b.exportedData())
        XCTAssertEqual(a.devices().first?.name, left.name)
        XCTAssertEqual(a.devices().first?.cursorSpeed, 1.75)
        let aUpload = await transport.uploaded(for: a.replicaID)
        let bUpload = await transport.uploaded(for: b.replicaID)
        XCTAssertNotNil(aUpload); XCTAssertNotNil(bUpload)
        XCTAssertNotEqual(a.replicaID, b.replicaID)
    }

    func testNetworkFailurePreservesLocalOfflineEditsAndDoesNotPublish() async throws {
        let (store, defaults) = try makeStore(); let transport = SyncTestTransport()
        await transport.configure(fetchFailure: .accountUnavailable)
        let exchange = DeviceSyncExchange(store: store, transport: transport, defaults: defaults)
        let local = device()
        do { _ = try await exchange.synchronize(localDevices: [local]); XCTFail("Expected unavailable cloud") }
        catch { XCTAssertEqual(error as? DeviceSyncFailure, .accountUnavailable) }
        XCTAssertEqual(store.devices().first?.name, local.name)
        XCTAssertEqual(try DeviceSyncStore(defaults: defaults).exportedData(), try store.exportedData())
        let counts = await transport.counts(); XCTAssertEqual(counts.publish, 0)
    }

    func testBoundAccountSurvivesRestartAndStopsUploadToDifferentAccount() async throws {
        let (store, defaults) = try makeStore(); let transport = SyncTestTransport()
        let exchange = DeviceSyncExchange(store: store, transport: transport, defaults: defaults)
        _ = try await exchange.synchronize(localDevices: [device()])
        let before = try store.exportedData()
        await transport.configure(account: "test-account-B")
        let reopened = DeviceSyncExchange(store: try DeviceSyncStore(defaults: defaults),
                                          transport: transport, defaults: defaults)
        do { _ = try await reopened.synchronize(localDevices: store.devices()); XCTFail("Expected account boundary") }
        catch { XCTAssertEqual(error as? DeviceSyncFailure, .accountChanged) }
        let counts = await transport.counts(); XCTAssertEqual(counts.fetch, 1); XCTAssertEqual(counts.publish, 1)
        XCTAssertEqual(defaults.data(forKey: DeviceSyncStore.documentKey), before)
    }

    func testAccountChangeDuringFetchPreventsImportAndUpload() async throws {
        let (store, defaults) = try makeStore(); let transport = SyncTestTransport()
        let local = device(); try store.recordLocalDevices([local]); let before = try store.exportedData()
        var remote = DeviceSyncDocument(replicaID: UUID()); try remote.recordLocalDevices([device()])
        let remoteData = try remote.encoded()
        await transport.seed(remoteData, for: remote.replicaID)
        await transport.configure(accountAfterFetch: "test-account-B")
        let exchange = DeviceSyncExchange(store: store, transport: transport, defaults: defaults)
        do { _ = try await exchange.synchronize(localDevices: [local]); XCTFail("Expected changed account") }
        catch { XCTAssertEqual(error as? DeviceSyncFailure, .accountChanged) }
        XCTAssertEqual(try store.exportedData(), before)
        let counts = await transport.counts(); XCTAssertEqual(counts.publish, 0)
    }

    func testCorruptFetchedReplicaRejectsWholeImportBatch() async throws {
        let (store, defaults) = try makeStore(); let transport = SyncTestTransport()
        let local = device(); try store.recordLocalDevices([local]); let before = try store.exportedData()
        var remote = DeviceSyncDocument(replicaID: UUID()); try remote.recordLocalDevices([device()])
        let remoteData = try remote.encoded()
        await transport.seed(remoteData, for: remote.replicaID)
        await transport.seed(Data("corrupt-replica".utf8), for: UUID())
        let exchange = DeviceSyncExchange(store: store, transport: transport, defaults: defaults)
        do { _ = try await exchange.synchronize(localDevices: [local]); XCTFail("Expected invalid batch") }
        catch { XCTAssertEqual(error as? DeviceSyncDocument.Failure, .invalidDocument) }
        XCTAssertEqual(try store.exportedData(), before)
        let counts = await transport.counts(); XCTAssertEqual(counts.publish, 0)
        XCTAssertThrowsError(try store.receiveDocuments([remote.encoded(), Data("broken".utf8)]))
        XCTAssertEqual(try store.exportedData(), before)
    }

    func testConditionalPublicationRefusesChangedCloudVersion() async throws {
        let (store, defaults) = try makeStore(); let transport = SyncTestTransport()
        let exchange = DeviceSyncExchange(store: store, transport: transport, defaults: defaults)
        _ = try await exchange.synchronize(localDevices: [device()])
        let cloudBefore = await transport.uploaded(for: store.replicaID)
        await transport.configure(staleOwnVersion: true)
        var edit = try XCTUnwrap(store.devices().first); edit.name = "Queued new name"
        do { _ = try await exchange.synchronize(localDevices: [edit]); XCTFail("Expected conflict") }
        catch { XCTAssertEqual(error as? DeviceSyncFailure, .remoteConflict) }
        let after = await transport.uploaded(for: store.replicaID)
        XCTAssertEqual(after, cloudBefore)
        XCTAssertEqual(store.devices().first?.name, edit.name)
        let counts = await transport.counts(); XCTAssertEqual(counts.publish, 1)
    }

    func testEditsDuringUploadRemainPendingAndAreUploadedNextTime() async throws {
        let (store, defaults) = try makeStore(); let transport = SyncTestTransport()
        let original = device()
        await transport.configure(onPublish: {
            var edit = try XCTUnwrap(store.devices().first); edit.cursorSpeed = 1.5
            try store.recordLocalDevices([edit])
        })
        let exchange = DeviceSyncExchange(store: store, transport: transport, defaults: defaults)
        let outcome = try await exchange.synchronize(localDevices: [original])
        XCTAssertEqual(outcome, .pendingLocalChanges)
        XCTAssertEqual(store.devices().first?.cursorSpeed, 1.5)
        await transport.configure()
        let complete = try await exchange.synchronize(localDevices: store.devices())
        XCTAssertEqual(complete, .synchronized)
        let uploaded = await transport.uploaded(for: store.replicaID)
        let remote = try XCTUnwrap(uploaded)
        XCTAssertEqual(remote, try store.exportedData())
    }

    func testCancellationReleasesBusyGateAndPreventsPublication() async throws {
        let (store, defaults) = try makeStore(); let transport = SyncTestTransport()
        let began = expectation(description: "Fetch in progress")
        await transport.configure(fetchDelay: true, fetchStarted: { began.fulfill() })
        let exchange = DeviceSyncExchange(store: store, transport: transport, defaults: defaults)
        let original = device()
        let task = Task { try await exchange.synchronize(localDevices: [original]) }
        await fulfillment(of: [began], timeout: 3)
        do { _ = try await exchange.synchronize(localDevices: [original]); XCTFail("Expected busy") }
        catch { XCTAssertEqual(error as? DeviceSyncFailure, .busy) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        let counts = await transport.counts(); XCTAssertEqual(counts.publish, 0)
        await transport.configure()
        let completed = try await exchange.synchronize(localDevices: store.devices())
        XCTAssertEqual(completed, .synchronized)
    }

    func testMoreThan32RemoteReplicasFailsWithoutPublishingOrDiscardingLocalData() async throws {
        let (store, defaults) = try makeStore(); let transport = SyncTestTransport()
        let original = device(); try store.recordLocalDevices([original]); let before = try store.exportedData()
        for _ in 0..<33 {
            let replica = UUID()
            let empty = try DeviceSyncDocument(replicaID: replica).encoded()
            await transport.seed(empty, for: replica)
        }
        let exchange = DeviceSyncExchange(store: store, transport: transport, defaults: defaults)
        do { _ = try await exchange.synchronize(localDevices: [original]); XCTFail("Expected replica limit") }
        catch { XCTAssertEqual(error as? DeviceSyncFailure, .tooManyReplicas) }
        XCTAssertEqual(try store.exportedData(), before)
        let counts = await transport.counts(); XCTAssertEqual(counts.publish, 0)
    }

    func testCloudRecordUsesEncryptedFieldAndCarriesOnlyCanonicalMetadata() throws {
        let replica = UUID(); var document = DeviceSyncDocument(replicaID: replica)
        try document.recordLocalDevices([device()]); let data = try document.encoded()
        let zone = CKRecordZone.ID(zoneName: DeviceCloudRecordCodec.zoneName, ownerName: "test-owner")
        let record = try DeviceCloudRecordCodec.record(document: data, replicaID: replica, zoneID: zone, version: nil)
        // allKeys also lists encrypted fields. Their encryptedValues membership defines protection.
        XCTAssertEqual(Set(record.allKeys()), [DeviceCloudRecordCodec.payloadKey])
        XCTAssertEqual(record.encryptedValues.allKeys(), [DeviceCloudRecordCodec.payloadKey])
        XCTAssertEqual(try DeviceCloudRecordCodec.document(from: record, zoneID: zone), data)
        let version = try DeviceCloudRecordCodec.version(of: record)
        let restored = try DeviceCloudRecordCodec.record(document: data, replicaID: replica, zoneID: zone, version: version)
        XCTAssertEqual(restored.recordID, record.recordID)
        XCTAssertEqual(try DeviceCloudRecordCodec.document(from: restored, zoneID: zone), data)
    }

    func testCloudVersionCannotBeReusedForAnotherReplicaOrAccountZone() throws {
        let replica = UUID(); let data = try DeviceSyncDocument(replicaID: replica).encoded()
        let zone = CKRecordZone.ID(zoneName: DeviceCloudRecordCodec.zoneName, ownerName: "test-owner-A")
        let record = try DeviceCloudRecordCodec.record(document: data, replicaID: replica, zoneID: zone, version: nil)
        let version = try DeviceCloudRecordCodec.version(of: record)
        XCTAssertThrowsError(try DeviceCloudRecordCodec.record(document: data, replicaID: UUID(), zoneID: zone, version: version))
        let other = CKRecordZone.ID(zoneName: DeviceCloudRecordCodec.zoneName, ownerName: "test-owner-B")
        XCTAssertThrowsError(try DeviceCloudRecordCodec.record(document: data, replicaID: replica, zoneID: other, version: version))
        XCTAssertThrowsError(try DeviceCloudRecordCodec.document(from: record, zoneID: other))
    }

    func testCloudRecordRejectsExtraFieldsAndInvalidVersionBytes() throws {
        let replica = UUID(); let original = try DeviceSyncDocument(replicaID: replica).encoded()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        object["unexpectedCredential"] = "synthetic-test-only"
        let altered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let zone = CKRecordZone.ID(zoneName: DeviceCloudRecordCodec.zoneName, ownerName: "test-owner")
        XCTAssertThrowsError(try DeviceCloudRecordCodec.record(document: altered, replicaID: replica, zoneID: zone, version: nil))
        XCTAssertThrowsError(try DeviceCloudRecordCodec.record(document: original, replicaID: replica, zoneID: zone, version: Data("broken".utf8)))
        XCTAssertThrowsError(try DeviceCloudRecordCodec.record(document: original, replicaID: replica, zoneID: zone, version: Data(repeating: 0, count: 65537)))
    }
}
