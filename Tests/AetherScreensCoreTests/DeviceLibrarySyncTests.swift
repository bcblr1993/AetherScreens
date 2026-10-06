import XCTest
@testable import AetherScreensCore
@testable import AetherScreensSSH

private final class LibrarySyncSecretBackend: SSHSecretBackend {
    private var values: [String: Data] = [:]
    private let lock = NSLock()
    func read(account: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }; return values[account]
    }
    func write(_ data: Data, account: String) throws {
        lock.lock(); defer { lock.unlock() }; values[account] = data
    }
    func insert(_ data: Data, account: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard values[account] == nil else { throw SSHKeychainStore.Failure.changedHostKey }
        values[account] = data
    }
    func delete(account: String) throws {
        lock.lock(); defer { lock.unlock() }; values.removeValue(forKey: account)
    }
}

final class DeviceLibrarySyncTests: XCTestCase {
    private var suites: [String] = []
    private var secrets: [(KeychainStore, UUID)] = []

    override func tearDown() {
        for (keys, id) in secrets { keys.deletePassword(forKey: id.uuidString) }
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        suites = []; secrets = []
        super.tearDown()
    }

    private func makeLibrary() throws -> (DeviceStore, UserDefaults, KeychainStore) {
        let suite = "test.aetherscreens.sync.library." + UUID().uuidString
        suites.append(suite)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let keys = KeychainStore(serviceName: suite, legacyServiceName: nil, backend: TestKeychainBackend())
        let library = TestStorage.make(userDefaults: defaults, keychain: keys,
                                  sshKeychain: TestStorage.sshKeychain())
        return (library, defaults, keys)
    }

    private func computer(_ name: String = "Local QA") -> RemoteDevice {
        RemoteDevice(name: name, host: "qa.invalid", isOnline: true,
                     lastConnected: Date(timeIntervalSince1970: 123))
    }

    private func remote(_ devices: [RemoteDevice]) throws -> Data {
        var document = DeviceSyncDocument(replicaID: UUID())
        try document.recordLocalDevices(devices)
        return try document.encoded()
    }

    func testLocalStorageNeedsNoReplicaAndNeverContactsCloud() throws {
        let (library, defaults, _) = try makeLibrary()
        library.addDevice(computer())
        XCTAssertEqual(library.storageMode, .local)
        XCTAssertNil(defaults.data(forKey: DeviceLibrarySyncCheckpoint.key))
        XCTAssertThrowsError(try library.synchronizationReplica()) {
            XCTAssertEqual($0 as? DeviceSyncFailure, .localStorageSelected)
        }
        try library.selectStorage(.local)
        XCTAssertEqual(library.storageMode, .local)
        XCTAssertEqual(library.devices.count, 1)
    }

    func testActualLibraryMutationsPersistOfflineMetadataAndDeletionAcrossRestart() throws {
        let (library, defaults, _) = try makeLibrary()
        let first = computer(); let removed = computer("Delete QA")
        library.addDevice(first); library.addDevice(removed)
        try library.selectStorage(.iCloud)
        let replica = try library.synchronizationReplica()
        var renamed = first; renamed.name = "Offline rename"
        library.updateDevice(renamed)
        library.updateCursorSpeed(1.75, for: first)
        library.updateSharedClipboard(false, for: first)
        library.updatePreferredDisplay(9, for: first)
        library.recordConnection(for: first)
        XCTAssertTrue(library.deleteDevice(removed))
        let exported = try replica.exportedData()
        let restarted = TestStorage.make(userDefaults: defaults)
        let restored = try XCTUnwrap(restarted.device(withID: first.id))
        XCTAssertEqual(restored.name, renamed.name)
        XCTAssertEqual(restored.cursorSpeed, 1.75)
        XCTAssertFalse(restored.effectiveSharedClipboard)
        XCTAssertEqual(restored.preferredDisplayID, 9)
        XCTAssertNotNil(restored.lastConnected)
        XCTAssertNil(restarted.device(withID: removed.id))
        XCTAssertEqual(try restarted.synchronizationReplica().replicaID, replica.replicaID)
        XCTAssertEqual(try restarted.synchronizationReplica().exportedData(), exported)
        XCTAssertFalse(String(decoding: exported, as: UTF8.self).contains("lastConnected"))
        XCTAssertFalse(String(decoding: exported, as: UTF8.self).contains("isOnline"))
        _ = try replica.receiveDocuments([remote([first, removed])])
        XCTAssertNil(library.device(withID: removed.id), "Old cloud data cannot undo a local deletion")
    }

    func testEditsDuringFetchMergeIntoActualLibraryWithoutOverwritingOtherPreferences() async throws {
        let (library, defaults, _) = try makeLibrary()
        let first = computer(); library.addDevice(first); try library.selectStorage(.iCloud)
        let replica = try library.synchronizationReplica()
        var document = try DeviceSyncDocument(data: replica.exportedData(), replicaID: UUID())
        var renamed = first; renamed.name = "Remote rename"
        try document.recordLocalDevices([renamed])
        let transport = SyncTestTransport()
        try await transport.seed(document.encoded(), for: document.replicaID)
        await transport.configure(fetchStarted: { library.updateCursorSpeed(1.5, for: first) })
        let exchange = DeviceSyncExchange(store: replica, transport: transport, defaults: defaults)
        let outcome = try await exchange.synchronize()
        XCTAssertEqual(outcome, .synchronized)
        let result = try XCTUnwrap(library.device(withID: first.id))
        XCTAssertEqual(result.name, renamed.name)
        XCTAssertEqual(result.cursorSpeed, 1.5)
        XCTAssertTrue(result.isOnline)
        XCTAssertEqual(result.lastConnected, first.lastConnected)
        XCTAssertEqual(TestStorage.make(userDefaults: defaults).device(withID: first.id), result)
    }

    func testPublishFailureKeepsImportedComputersAndRetryDoesNotDeleteUnseenRows() async throws {
        let (library, defaults, _) = try makeLibrary()
        let first = computer(); let incoming = computer("Remote new computer")
        library.addDevice(first); try library.selectStorage(.iCloud)
        let replica = try library.synchronizationReplica()
        let transport = SyncTestTransport(); let remoteID = UUID()
        try await transport.seed(remote([incoming]), for: remoteID)
        await transport.configure(publishFailure: .remoteConflict)
        let exchange = DeviceSyncExchange(store: replica, transport: transport, defaults: defaults)
        do { _ = try await exchange.synchronize(); XCTFail("Expected publication failure") }
        catch { XCTAssertEqual(error as? DeviceSyncFailure, .remoteConflict) }
        XCTAssertEqual(Set(library.devices.map(\.id)), [first.id, incoming.id])
        let restarted = TestStorage.make(userDefaults: defaults)
        await transport.configure()
        let replacement = try restarted.synchronizationReplica()
        let retry = DeviceSyncExchange(store: replacement, transport: transport, defaults: defaults)
        _ = try await retry.synchronize()
        XCTAssertEqual(Set(restarted.devices.map(\.id)), [first.id, incoming.id])
        let bytes = await transport.uploaded(for: replacement.replicaID)
        let published = try DeviceSyncDocument(data: XCTUnwrap(bytes), replicaID: UUID())
        XCTAssertEqual(Set(published.devices().map(\.id)), [first.id, incoming.id])
    }

    func testLocalSelectionDuringFetchStopsImportAndPublication() async throws {
        let (library, defaults, _) = try makeLibrary()
        let first = computer(); library.addDevice(first); try library.selectStorage(.iCloud)
        let replica = try library.synchronizationReplica()
        let transport = SyncTestTransport()
        try await transport.seed(remote([computer("Unseen cloud computer")]), for: UUID())
        await transport.configure(fetchStarted: { try? library.selectStorage(.local) })
        let exchange = DeviceSyncExchange(store: replica, transport: transport, defaults: defaults)
        do { _ = try await exchange.synchronize(); XCTFail("Expected changed storage") }
        catch { XCTAssertEqual(error as? DeviceSyncFailure, .configurationChanged) }
        XCTAssertEqual(library.storageMode, .local)
        XCTAssertEqual(library.devices, [first])
        let counts = await transport.counts(); XCTAssertEqual(counts.publish, 0)
        try library.selectStorage(.iCloud)
        XCTAssertThrowsError(try replica.exportedData()) {
            XCTAssertEqual($0 as? DeviceSyncFailure, .configurationChanged)
        }
    }

    func testLocalEditDuringPublicationRemainsPendingInActualLibrary() async throws {
        let (library, defaults, _) = try makeLibrary()
        let first = computer(); library.addDevice(first); try library.selectStorage(.iCloud)
        let replica = try library.synchronizationReplica(); let transport = SyncTestTransport()
        await transport.configure(onPublish: { library.updateSharedClipboard(false, for: first) })
        let exchange = DeviceSyncExchange(store: replica, transport: transport, defaults: defaults)
        let outcome = try await exchange.synchronize()
        XCTAssertEqual(outcome, .pendingLocalChanges)
        XCTAssertFalse(try XCTUnwrap(library.device(withID: first.id)).effectiveSharedClipboard)
        await transport.configure()
        let completed = try await exchange.synchronize()
        XCTAssertEqual(completed, .synchronized)
    }

    func testLocalSelectionDuringAccountLookupStopsBeforeFetchingMetadata() async throws {
        let (library, defaults, _) = try makeLibrary()
        let first = computer(); library.addDevice(first); try library.selectStorage(.iCloud)
        let replica = try library.synchronizationReplica(); let transport = SyncTestTransport()
        await transport.configure(accountStarted: { try? library.selectStorage(.local) })
        let exchange = DeviceSyncExchange(store: replica, transport: transport, defaults: defaults)
        do { _ = try await exchange.synchronize(); XCTFail("Expected cancelled storage selection") }
        catch { XCTAssertEqual(error as? DeviceSyncFailure, .configurationChanged) }
        let counts = await transport.counts()
        XCTAssertEqual(counts.fetch, 0); XCTAssertEqual(counts.publish, 0)
        XCTAssertEqual(library.devices, [first])
    }

    func testCloudEndpointChangeDoesNotRebindSSHSecretAndExplicitReplacementRestoresAccess() throws {
        let (_, defaults, _) = try makeLibrary()
        let backend = LibrarySyncSecretBackend(); let keys = SSHKeychainStore(backend: backend)
        let library = TestStorage.make(userDefaults: defaults, sshKeychain: keys)
        var first = computer()
        first.sshConfiguration = try SSHConfiguration(host: "ssh.qa.invalid", username: "qa-user")
        library.addDevice(first)
        let configuration = try XCTUnwrap(first.sshConfiguration)
        try keys.save(.password("synthetic-ssh-password-qa"), for: first.id, configuration: configuration)
        try library.selectStorage(.iCloud)
        let replica = try library.synchronizationReplica()
        XCTAssertNotNil(try library.getSSHCredentials(for: first))
        var incoming = try DeviceSyncDocument(data: replica.exportedData(), replicaID: UUID())
        var changed = first; changed.host = "different.rfb.qa.invalid"
        try incoming.recordLocalDevices([changed])
        _ = try replica.receiveDocuments([incoming.encoded()])
        XCTAssertThrowsError(try library.getSSHCredentials(for: changed)) {
            XCTAssertEqual($0 as? SSHKeychainStore.Failure, .credentialMismatch)
        }
        XCTAssertNotNil(try keys.load(for: first.id, configuration: configuration), "Import must not delete the user's local secret")
        let reopened = TestStorage.make(userDefaults: defaults, sshKeychain: keys)
        XCTAssertThrowsError(try reopened.getSSHCredentials(for: changed))
        try reopened.updateConnection(changed, password: nil, sshCredentials: .password("synthetic-replacement-ssh-qa"))
        XCTAssertNotNil(try reopened.getSSHCredentials(for: changed))
        let exported = try reopened.synchronizationReplica().exportedData()
        XCTAssertFalse(String(decoding: exported, as: UTF8.self).contains("synthetic-ssh-password-qa"))
        XCTAssertFalse(String(decoding: exported, as: UTF8.self).contains("synthetic-replacement-ssh-qa"))
    }

    func testCloudEndpointEditInvalidatesLocalPasswordWithoutDeletingOrExportingIt() throws {
        let (library, defaults, keys) = try makeLibrary()
        let first = computer(); let secret = "synthetic-local-password-qa"
        secrets.append((keys, first.id)); library.addDevice(first, password: secret)
        try library.selectStorage(.iCloud)
        let replica = try library.synchronizationReplica()
        XCTAssertEqual(library.getPassword(for: first), secret)
        var incoming = try DeviceSyncDocument(data: replica.exportedData(), replicaID: UUID())
        var changed = first; changed.host = "other.qa.invalid"
        try incoming.recordLocalDevices([changed])
        _ = try replica.receiveDocuments([incoming.encoded()])
        let restored = try XCTUnwrap(library.device(withID: first.id))
        XCTAssertEqual(restored.host, changed.host)
        XCTAssertNil(library.getPassword(for: restored))
        XCTAssertEqual(keys.loadPassword(forKey: first.id.uuidString), secret)
        let reopened = TestStorage.make(userDefaults: defaults, keychain: keys)
        XCTAssertNil(reopened.getPassword(for: restored))
        reopened.updatePassword("synthetic-new-password-qa", for: restored)
        XCTAssertEqual(reopened.getPassword(for: restored), "synthetic-new-password-qa")
        XCTAssertNil(reopened.getPassword(for: first), "A stale session cannot read the replacement target's secret")
        let outgoing = try reopened.synchronizationReplica().exportedData()
        XCTAssertFalse(String(decoding: outgoing, as: UTF8.self).contains(secret))
        XCTAssertFalse(String(decoding: outgoing, as: UTF8.self).contains("synthetic-new-password-qa"))
    }

    func testInvalidRemoteBatchLeavesLibraryAndCheckpointUnchanged() throws {
        let (library, defaults, _) = try makeLibrary()
        let first = computer(); library.addDevice(first); try library.selectStorage(.iCloud)
        let before = defaults.data(forKey: DeviceLibrarySyncCheckpoint.key)
        let replica = try library.synchronizationReplica()
        XCTAssertThrowsError(try replica.receiveDocuments([remote([computer("New cloud computer")]), Data("broken".utf8)]))
        XCTAssertEqual(library.devices, [first])
        XCTAssertEqual(defaults.data(forKey: DeviceLibrarySyncCheckpoint.key), before)
    }

    func testRestartUsesAtomicCheckpointWhenCompatibilityMirrorWasInterrupted() throws {
        let (library, defaults, _) = try makeLibrary()
        let first = computer(); library.addDevice(first); try library.selectStorage(.iCloud)
        let before = defaults.data(forKey: DeviceStore.storageKey)
        let replica = try library.synchronizationReplica(); let incoming = computer("Remote computer")
        _ = try replica.receiveDocuments([remote([incoming])])
        defaults.set(before, forKey: DeviceStore.storageKey)
        let restarted = TestStorage.make(userDefaults: defaults)
        XCTAssertEqual(Set(restarted.devices.map(\.id)), [first.id, incoming.id])
        XCTAssertNil(restarted.synchronizationFailure)
        _ = try restarted.synchronizationReplica().exportedData()
        XCTAssertEqual(try JSONDecoder().decode([RemoteDevice].self, from: XCTUnwrap(defaults.data(forKey: DeviceStore.storageKey))), restarted.devices)
    }

    func testCorruptCheckpointIsPreservedWhileLocalEditsRemainAvailable() throws {
        let (library, defaults, _) = try makeLibrary()
        library.addDevice(computer())
        let corrupt = Data("corrupt-checkpoint".utf8)
        defaults.set(corrupt, forKey: DeviceLibrarySyncCheckpoint.key)
        let restarted = TestStorage.make(userDefaults: defaults)
        XCTAssertEqual(restarted.synchronizationFailure, .invalidDocument)
        XCTAssertThrowsError(try restarted.selectStorage(.iCloud))
        restarted.addDevice(computer("New local computer"))
        XCTAssertEqual(TestStorage.make(userDefaults: defaults).devices.count, 2)
        XCTAssertEqual(defaults.data(forKey: DeviceLibrarySyncCheckpoint.key), corrupt)
    }

    func testStaleLibraryInstanceCannotOverwriteAnotherInstancesNewComputers() throws {
        let (library, defaults, _) = try makeLibrary()
        let first = computer(); library.addDevice(first); try library.selectStorage(.iCloud)
        let stale = TestStorage.make(userDefaults: defaults)
        let added = computer("Added in current instance"); library.addDevice(added)
        stale.updateCursorSpeed(2, for: first)
        XCTAssertEqual(stale.synchronizationFailure, .staleLocalReplica)
        XCTAssertEqual(Set(TestStorage.make(userDefaults: defaults).devices.map(\.id)), [first.id, added.id])
        XCTAssertThrowsError(try stale.synchronizationReplica().exportedData())
    }

    func testLocalStorageDoesNotInheritCloudDocumentQuota() throws {
        let (library, defaults, _) = try makeLibrary()
        let many = (0..<1025).map { computer("Local \($0)") }
        defaults.set(try JSONEncoder().encode(many), forKey: DeviceStore.storageKey)
        library.loadDevices()
        try library.selectStorage(.local)
        XCTAssertEqual(library.devices.count, 1025)
        XCTAssertThrowsError(try library.selectStorage(.iCloud)) {
            XCTAssertEqual($0 as? DeviceSyncDocument.Failure, .quotaExceeded)
        }
        XCTAssertEqual(library.storageMode, .local)
        XCTAssertEqual(TestStorage.make(userDefaults: defaults).devices.count, 1025)
    }
}
