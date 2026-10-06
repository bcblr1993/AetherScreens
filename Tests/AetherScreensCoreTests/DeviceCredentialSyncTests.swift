import XCTest
import Security
import LocalAuthentication
import CloudKit
@testable import AetherScreensCore
@testable import AetherScreensSSH

private final class CredentialCloud: @unchecked Sendable {
    var values: [String: Data] = [:]
    let lock = NSRecursiveLock()
}

private final class CredentialBackend: DeviceCredentialBackend, @unchecked Sendable {
    let remote: CredentialCloud
    var local: [String: Data] = [:]
    var cloudCalls = 0
    var failCloudWrites = false
    var failLocalWrites = false
    var insertRace: Data?
    init(remote: CredentialCloud = CredentialCloud()) { self.remote = remote }
    func read(account: String, cloud: Bool) throws -> Data? {
        remote.lock.lock(); defer { remote.lock.unlock() }
        if cloud { cloudCalls += 1; return remote.values[account] }
        return local[account]
    }
    func write(_ data: Data, account: String, cloud: Bool) throws {
        remote.lock.lock(); defer { remote.lock.unlock() }
        if cloud {
            cloudCalls += 1
            if failCloudWrites { throw DeviceCredentialSyncStore.Failure.keychain(errSecInteractionNotAllowed) }
            remote.values[account] = data
        } else {
            if failLocalWrites { throw DeviceCredentialSyncStore.Failure.keychain(errSecInteractionNotAllowed) }
            local[account] = data
        }
    }
    func insert(_ data: Data, account: String, cloud: Bool) throws {
        remote.lock.lock(); defer { remote.lock.unlock() }
        if cloud {
            cloudCalls += 1
            if failCloudWrites { throw DeviceCredentialSyncStore.Failure.keychain(errSecInteractionNotAllowed) }
            if let race = insertRace { remote.values[account] = race; insertRace = nil }
            guard remote.values[account] == nil else { throw DeviceCredentialSyncStore.Failure.keychain(errSecDuplicateItem) }
            remote.values[account] = data
        } else {
            guard local[account] == nil else { throw DeviceCredentialSyncStore.Failure.keychain(errSecDuplicateItem) }
            local[account] = data
        }
    }
    func delete(account: String, cloud: Bool) throws {
        remote.lock.lock(); defer { remote.lock.unlock() }
        if cloud { cloudCalls += 1; remote.values.removeValue(forKey: account) }
        else { local.removeValue(forKey: account) }
    }
}

private final class CredentialLegacyPasswords: DevicePasswordStore, @unchecked Sendable {
    var values: [String: String] = [:]
    func savePassword(_ password: String, forKey key: String) -> Bool { values[key] = password; return true }
    func loadPassword(forKey key: String) -> String? { values[key] }
    func deletePassword(forKey key: String) -> Bool { values.removeValue(forKey: key); return true }
}

private final class CredentialLegacySSH: SSHSecretBackend {
    var values: [String: Data] = [:]
    func read(account: String) throws -> Data? { values[account] }
    func write(_ data: Data, account: String) throws { values[account] = data }
    func insert(_ data: Data, account: String) throws {
        guard values[account] == nil else { throw SSHKeychainStore.Failure.keychain(errSecDuplicateItem) }
        values[account] = data
    }
    func delete(account: String) throws { values.removeValue(forKey: account) }
}

private final class CredentialSecurityAPI: DeviceCredentialSecurityAPI, @unchecked Sendable {
    var calls: [(String, [String: Any])] = []
    var updateStatuses = [errSecSuccess]
    var addStatus = errSecSuccess
    var copyStatus = errSecItemNotFound
    var copied: Data?
    func copy(_ query: [String: Any]) -> (OSStatus, Data?) {
        calls.append(("copy", query)); return (copyStatus, copied)
    }
    func update(_ query: [String: Any], data: Data) -> OSStatus {
        calls.append(("update", query)); return updateStatuses.removeFirst()
    }
    func add(_ query: [String: Any]) -> OSStatus { calls.append(("add", query)); return addStatus }
    func delete(_ query: [String: Any]) -> OSStatus { calls.append(("delete", query)); return errSecSuccess }
}

final class DeviceCredentialSyncTests: XCTestCase {
    private var suites: [String] = []
    override func tearDown() {
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        suites = []; super.tearDown()
    }
    private func defaults() throws -> UserDefaults {
        let suite = "test.aetherscreens.credential-sync." + UUID().uuidString
        suites.append(suite); return try XCTUnwrap(UserDefaults(suiteName: suite))
    }
    private func provider(_ backend: CredentialBackend, _ defaults: UserDefaults) -> DeviceCredentialSyncStore {
        DeviceCredentialSyncStore(backend: backend, defaults: defaults, namespace: "fixture")
    }
    private func device(ssh: Bool = false) throws -> RemoteDevice {
        RemoteDevice(name: "Synthetic QA", host: "desktop.qa.invalid", authMethod: .macAccount,
                     username: "qa-account", sshConfiguration: ssh ? try SSHConfiguration(host: "jump.qa.invalid", username: "qa-ssh") : nil)
    }
    private func flush(_ store: DeviceCredentialSyncStore, _ devices: [RemoteDevice], deleted: Set<UUID> = [],
                       password: String? = nil) throws {
        store.setCloudAccess(true)
        try store.synchronize(devices: devices, deletedIDs: deleted, localPassword: { _ in password }, localSSH: { _ in nil })
    }
    private func password(_ store: DeviceCredentialSyncStore, _ device: RemoteDevice) throws -> String? {
        switch try store.password(for: device) { case .value(let value): return value; default: return nil }
    }
    private func library(_ defaults: UserDefaults) -> (DeviceStore, CredentialLegacyPasswords, CredentialLegacySSH) {
        let passwords = CredentialLegacyPasswords(); let ssh = CredentialLegacySSH()
        return (TestStorage.make(userDefaults: defaults, passwordStore: passwords, sshKeychain: SSHKeychainStore(backend: ssh)), passwords, ssh)
    }
    private func document(_ devices: [RemoteDevice]) throws -> (Data, UUID) {
        var document = DeviceSyncDocument(replicaID: UUID()); try document.recordLocalDevices(devices)
        return (try document.encoded(), document.replicaID)
    }

    func testOfflineStagingSurvivesRestartWithoutSecretsInPreferences() throws {
        let backend = CredentialBackend(); let defaults = try defaults(); let device = try device()
        try provider(backend, defaults).stagePassword("synthetic-offline-password", for: device)
        let restarted = provider(backend, defaults)
        XCTAssertEqual(try password(restarted, device), "synthetic-offline-password")
        XCTAssertEqual(backend.cloudCalls, 0)
        let encoded = try PropertyListSerialization.data(fromPropertyList: defaults.dictionaryRepresentation(), format: .xml, options: 0)
        let text = String(decoding: encoded, as: UTF8.self)
        for excluded in ["synthetic-offline-password", device.host, device.username!] { XCTAssertFalse(text.contains(excluded)) }
        try flush(restarted, [device])
        XCTAssertTrue(backend.local.keys.allSatisfy { !$0.hasPrefix("pending:") })
        let second = provider(CredentialBackend(remote: backend.remote), try self.defaults())
        second.setCloudAccess(true)
        XCTAssertEqual(try password(second, device), "synthetic-offline-password")
    }

    func testBindingRejectsEveryConnectionChangeButAllowsPresentationChanges() throws {
        let backend = CredentialBackend(); let store = provider(backend, try defaults()); let device = try device(ssh: true)
        try store.stagePassword("synthetic-bound-password", for: device)
        var presentation = device; presentation.name = "Renamed QA"; presentation.preferredDisplayID = 9; presentation.cursorSpeed = 1.5
        XCTAssertEqual(try password(store, presentation), "synthetic-bound-password")
        var variants: [RemoteDevice] = []
        var changed = device; changed.host = "other.qa.invalid"; variants.append(changed)
        changed = device; changed.port = 5999; variants.append(changed)
        changed = device; changed.username = "other-qa"; variants.append(changed)
        changed = device; changed.authMethod = .vncPassword; variants.append(changed)
        changed = device; changed.sshConfiguration = try SSHConfiguration(host: "jump.qa.invalid", username: "qa-ssh", destinationHost: "other.qa.invalid"); variants.append(changed)
        for variant in variants {
            XCTAssertThrowsError(try store.password(for: variant)) { XCTAssertEqual($0 as? DeviceCredentialSyncStore.Failure, .credentialMismatch) }
        }
    }

    func testFailedUploadRetainsStagedSecretAndRetryAfterRestart() throws {
        let backend = CredentialBackend(); let defaults = try defaults(); let device = try device(); let store = provider(backend, defaults)
        try store.stagePassword("synthetic-retry-password", for: device); backend.failCloudWrites = true
        XCTAssertThrowsError(try flush(store, [device]))
        XCTAssertEqual(try password(store, device), "synthetic-retry-password")
        XCTAssertTrue(backend.local.keys.contains { $0.hasPrefix("pending:") })
        backend.failCloudWrites = false
        try flush(provider(backend, defaults), [device])
        XCTAssertFalse(backend.local.keys.contains { $0.hasPrefix("pending:") })
    }

    func testKnownRemoteChangeDoesNotGetOverwrittenByOfflineRetry() throws {
        let cloud = CredentialCloud(); let firstBackend = CredentialBackend(remote: cloud)
        let first = provider(firstBackend, try defaults()); let device = try device()
        try first.stagePassword("synthetic-first", for: device); try flush(first, [device])
        first.setCloudAccess(false); try first.stagePassword("synthetic-offline-edit", for: device)
        let second = provider(CredentialBackend(remote: cloud), try defaults()); second.setCloudAccess(true)
        _ = try second.password(for: device); try second.stagePassword("synthetic-other-edit", for: device); try flush(second, [device])
        let expected = cloud.values
        XCTAssertThrowsError(try flush(first, [device])) { XCTAssertEqual($0 as? DeviceCredentialSyncStore.Failure, .conflict) }
        XCTAssertEqual(cloud.values, expected)
        XCTAssertTrue(firstBackend.local.keys.contains { $0.hasPrefix("pending:") })
        try first.stagePassword("synthetic-explicit-conflict-resolution", for: device)
        try flush(first, [device])
        XCTAssertEqual(try password(second, device), "synthetic-explicit-conflict-resolution")
    }

    func testStaleEndpointQueueCannotUploadToEditedTarget() throws {
        let backend = CredentialBackend(); let store = provider(backend, try defaults()); let device = try device()
        try store.stagePassword("synthetic-stale", for: device)
        var edited = device; edited.host = "edited.qa.invalid"
        XCTAssertThrowsError(try flush(store, [edited])) { XCTAssertEqual($0 as? DeviceCredentialSyncStore.Failure, .credentialMismatch) }
        XCTAssertTrue(backend.remote.values.isEmpty)
    }

    func testClearTombstoneWinsOverLegacyBootstrapAndCachedValue() throws {
        let backend = CredentialBackend(); let store = provider(backend, try defaults()); let device = try device()
        try store.stagePassword("synthetic-old", for: device); try flush(store, [device])
        try store.stagePasswordDeletion(for: device.id); try flush(store, [device], password: "synthetic-legacy-old")
        guard case .deleted = try store.password(for: device) else { return XCTFail("Expected deletion") }
        store.setCloudAccess(false)
        guard case .deleted = try store.password(for: device) else { return XCTFail("Expected cached deletion") }
        let second = provider(CredentialBackend(remote: backend.remote), try defaults())
        try flush(second, [device], password: "synthetic-legacy-old")
        guard case .deleted = try second.password(for: device) else { return XCTFail("Legacy secret was resurrected") }
    }

    func testDeletedMetadataClearsQueuedPasswordAndSSHWithoutRecreatingComputer() throws {
        let backend = CredentialBackend(); let store = provider(backend, try defaults()); let device = try device(ssh: true)
        try store.stagePassword("synthetic-delete-password", for: device)
        try store.stageSSH(.password("synthetic-delete-ssh"), for: device)
        try flush(store, [], deleted: [device.id])
        XCTAssertEqual(backend.remote.values.count, 2)
        XCTAssertFalse(backend.local.keys.contains { $0.hasPrefix("pending:") })
        guard case .deleted = try store.sshCredentials(for: device) else { return XCTFail("SSH deletion missing") }
    }

    func testBootstrapDuplicateRacePreservesUnseenRemoteCredential() throws {
        let otherBackend = CredentialBackend(); let other = provider(otherBackend, try defaults()); let device = try device()
        try other.stagePassword("synthetic-unseen", for: device); try flush(other, [device])
        let backend = CredentialBackend(); backend.insertRace = try XCTUnwrap(otherBackend.remote.values.values.first)
        let store = provider(backend, try defaults()); try flush(store, [device], password: "synthetic-local-old")
        XCTAssertEqual(try password(store, device), "synthetic-unseen")
    }

    func testMalformedAndOversizedCloudRecordsFailClosed() throws {
        let backend = CredentialBackend(); let store = provider(backend, try defaults()); let device = try device()
        store.setCloudAccess(true)
        for bytes in [Data("{}".utf8), Data(repeating: 65, count: 128 * 1024 + 1)] {
            backend.remote.values["password:" + device.id.uuidString] = bytes
            XCTAssertThrowsError(try store.password(for: device)) { XCTAssertEqual($0 as? DeviceCredentialSyncStore.Failure, .invalidRecord) }
        }
    }

    func testInvalidPrivateKeyAndPassphraseBoundsCannotEnterQueue() throws {
        let backend = CredentialBackend(); let store = provider(backend, try defaults())
        var device = try device(); device.sshConfiguration = try SSHConfiguration(host: "jump.qa.invalid", username: "qa-ssh", authentication: .ed25519)
        XCTAssertThrowsError(try store.stageSSH(.ed25519PrivateKey("synthetic-invalid-key", passphrase: nil), for: device))
        XCTAssertTrue(backend.local.isEmpty); XCTAssertEqual(backend.cloudCalls, 0)
        XCTAssertThrowsError(try store.stagePassword(String(repeating: "x", count: 65_537), for: device))
    }

    func testSecurityQueriesSeparateEncryptedLocalStagingAndCloudAccessGroups() throws {
        let api = CredentialSecurityAPI()
        let backend = SystemDeviceCredentialBackend(service: "synthetic.service", accessGroup: "TESTTEAM.synthetic.shared", api: api)
        try backend.insert(Data([1]), account: "synthetic", cloud: true)
        try backend.insert(Data([2]), account: "synthetic", cloud: false)
        let cloud = api.calls[0].1; let local = api.calls[1].1
        for query in [cloud, local] {
            XCTAssertEqual(query[kSecAttrAccessGroup as String] as? String, "TESTTEAM.synthetic.shared")
            XCTAssertEqual(query[kSecUseDataProtectionKeychain as String] as? Bool, true)
            XCTAssertEqual((query[kSecUseAuthenticationContext as String] as? LAContext)?.interactionNotAllowed, true)
        }
        XCTAssertEqual(cloud[kSecAttrSynchronizable as String] as? Bool, true)
        XCTAssertEqual(local[kSecAttrSynchronizable as String] as? Bool, false)
        XCTAssertEqual(cloud[kSecAttrAccessible as String] as? String, kSecAttrAccessibleAfterFirstUnlock as String)
        XCTAssertEqual(local[kSecAttrAccessible as String] as? String, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }

    func testSystemWriteUpdatesBeforeInsertAndDuplicateRetryNeverDeletes() throws {
        let api = CredentialSecurityAPI(); api.updateStatuses = [errSecItemNotFound, errSecSuccess]; api.addStatus = errSecDuplicateItem
        let backend = SystemDeviceCredentialBackend(service: "synthetic", accessGroup: "TEST.synthetic", api: api)
        try backend.write(Data([1]), account: "synthetic", cloud: true)
        XCTAssertEqual(api.calls.map(\.0), ["update", "add", "update"])
        api.calls = []; api.updateStatuses = [errSecInteractionNotAllowed]
        XCTAssertThrowsError(try backend.write(Data([2]), account: "synthetic", cloud: true))
        XCTAssertEqual(api.calls.map(\.0), ["update"])
    }

    func testAccountNamespaceIsOpaqueAndConfigurationCannotBeWildcard() throws {
        let first = DeviceCredentialSyncStore.namespace(container: "iCloud.qa", account: "account-a")
        XCTAssertEqual(first.count, 64)
        XCTAssertNotEqual(first, DeviceCredentialSyncStore.namespace(container: "iCloud.qa", account: "account-b"))
        XCTAssertNotEqual(DeviceCredentialSyncStore.namespace(container: "iCloud.a", account: "bc"),
                          DeviceCredentialSyncStore.namespace(container: "iCloud.ab", account: "c"))
        XCTAssertThrowsError(try DeviceCredentialSyncStore(containerIdentifier: "iCloud.qa", verifiedAccount: "qa", accessGroup: "TEAM.*", defaults: try defaults()))
        XCTAssertThrowsError(try DeviceCredentialSyncStore(containerIdentifier: "invalid", verifiedAccount: "qa", accessGroup: "TEAM.qa", defaults: try defaults()))
    }

    func testActualImportedLibraryReadsVNCAndSSHButDoesNotImportHostPins() throws {
        let cloud = CredentialCloud(); let source = provider(CredentialBackend(remote: cloud), try defaults()); let device = try device(ssh: true)
        try source.stagePassword("synthetic-vnc", for: device); try source.stageSSH(.password("synthetic-ssh"), for: device)
        try flush(source, [device])
        let defaults = try self.defaults(); let (library, _, ssh) = library(defaults)
        try library.selectStorage(.iCloud)
        _ = try library.synchronizationReplica().receiveDocuments([document([device]).0])
        XCTAssertNil(library.getPassword(for: device))
        try library.synchronizeCredentials(using: provider(CredentialBackend(remote: cloud), defaults))
        XCTAssertEqual(library.getPassword(for: device), "synthetic-vnc")
        guard case .password(let value) = try library.getSSHCredentials(for: device) else { return XCTFail("Expected imported SSH credential") }
        XCTAssertEqual(value, "synthetic-ssh"); XCTAssertTrue(ssh.values.isEmpty)
        XCTAssertNil(try library.trustedSSHIdentity(for: device))
        let exported = String(decoding: try library.synchronizationReplica().exportedData(), as: UTF8.self)
        XCTAssertFalse(exported.contains("synthetic-vnc")); XCTAssertFalse(exported.contains("synthetic-ssh"))
    }

    func testLocalSelectionAndAccountSuspensionKeepBoundLocalCacheWithoutCloudQueries() throws {
        let cloud = CredentialCloud(); let device = try device(); let source = provider(CredentialBackend(remote: cloud), try defaults())
        try source.stagePassword("synthetic-local-cache", for: device); try flush(source, [device])
        let defaults = try self.defaults(); let (library, _, _) = library(defaults); try library.selectStorage(.iCloud)
        _ = try library.synchronizationReplica().receiveDocuments([document([device]).0])
        let backend = CredentialBackend(remote: cloud)
        try library.synchronizeCredentials(using: provider(backend, defaults))
        try library.selectStorage(.local); let calls = backend.cloudCalls
        XCTAssertEqual(library.getPassword(for: device), "synthetic-local-cache"); XCTAssertEqual(backend.cloudCalls, calls)
        library.suspendCredentialSynchronization()
        XCTAssertEqual(library.getPassword(for: device), "synthetic-local-cache"); XCTAssertEqual(backend.cloudCalls, calls)
    }

    func testActualConnectionSaveFailureIsVisibleAndDoesNotAddComputer() throws {
        let defaults = try self.defaults(); let (library, _, _) = library(defaults); try library.selectStorage(.iCloud)
        let backend = CredentialBackend(); try library.synchronizeCredentials(using: provider(backend, defaults))
        backend.failLocalWrites = true
        let request = try XCTUnwrap(ConnectionRequest(host: "desktop.qa.invalid", username: "qa-account", password: "synthetic-save-failure"))
        XCTAssertThrowsError(try library.saveConnection(request))
        XCTAssertNil(library.device(withID: request.device.id)); XCTAssertNotNil(library.credentialSynchronizationFailure)
        XCTAssertTrue(backend.remote.values.isEmpty)
    }

    func testLocalLegacyCredentialDoesNotFollowEditedHostOrAccountAfterRestart() throws {
        let defaults = try self.defaults(); let (library, legacy, _) = library(defaults); let device = try device()
        library.addDevice(device, password: "synthetic-local-original")
        var changed = device; changed.host = "changed.qa.invalid"
        library.updateDevice(changed)
        XCTAssertNil(library.getPassword(for: changed)); XCTAssertNil(library.getPassword(for: device))
        let restarted = TestStorage.make(userDefaults: defaults, passwordStore: legacy, sshKeychain: SSHKeychainStore(backend: CredentialLegacySSH()))
        XCTAssertNil(restarted.getPassword(for: changed))
        restarted.updatePassword("synthetic-local-replacement", for: changed)
        XCTAssertEqual(restarted.getPassword(for: changed), "synthetic-local-replacement")
        changed.username = "changed-account"; restarted.updateDevice(changed)
        XCTAssertNil(restarted.getPassword(for: changed))
        XCTAssertEqual(restarted.storageMode, .local)
    }

    func testActualClearPasswordKeepsTombstoneAcrossRestartAndCannotReviveLegacySecret() throws {
        let defaults = try self.defaults(); let (library, legacy, _) = library(defaults); let device = try device()
        library.addDevice(device, password: "synthetic-before-clear")
        library.clearPassword(for: device)
        // Simulate a stale/failed legacy system deletion independently of its in-memory cache.
        legacy.values[device.id.uuidString] = "synthetic-stale-legacy"
        let restarted = TestStorage.make(userDefaults: defaults, passwordStore: legacy, sshKeychain: SSHKeychainStore(backend: CredentialLegacySSH()))
        XCTAssertNil(restarted.getPassword(for: device))
    }

    func testActualSSHRemovalMasksOldSyncedCredentialAndPreservesLocalTrustEntries() throws {
        let defaults = try self.defaults(); let (library, _, ssh) = library(defaults); let device = try device(ssh: true)
        library.addDevice(device); try library.selectStorage(.iCloud)
        let backend = CredentialBackend(); let store = provider(backend, defaults)
        try store.stageSSH(.password("synthetic-ssh-before-removal"), for: device)
        try library.synchronizeCredentials(using: store)
        ssh.values["host:synthetic-approved-host"] = Data([1, 2, 3])
        var removed = device; removed.sshConfiguration = nil
        try library.updateConnection(removed, password: nil, sshCredentials: nil)
        XCTAssertNil(try library.getSSHCredentials(for: removed))
        try library.synchronizeCredentials(using: store)
        XCTAssertEqual(ssh.values["host:synthetic-approved-host"], Data([1, 2, 3]))
        guard case .deleted = try store.sshCredentials(for: removed) else { return XCTFail("SSH tombstone missing") }
    }

    func testValidEncryptedPrivateKeyAndPassphraseRoundTripWithoutPlainPreferences() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aetherscreens-sync-synthetic-key-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let keyURL = directory.appendingPathComponent("qa-key")
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        process.arguments = ["-q", "-t", "ed25519", "-N", "synthetic-sync-key-passphrase", "-C", "qa-fixture", "-f", keyURL.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
        let key = try String(contentsOf: keyURL, encoding: .utf8)
        var device = try self.device(); device.sshConfiguration = try SSHConfiguration(host: "jump.qa.invalid", username: "qa-ssh", authentication: .ed25519)
        let backend = CredentialBackend(); let defaults = try self.defaults(); let source = provider(backend, defaults)
        try source.stageSSH(.ed25519PrivateKey(key, passphrase: "synthetic-sync-key-passphrase"), for: device)
        try flush(source, [device])
        let second = provider(CredentialBackend(remote: backend.remote), try self.defaults()); second.setCloudAccess(true)
        guard case .value(.ed25519PrivateKey(let received, let passphrase)) = try second.sshCredentials(for: device) else {
            return XCTFail("Encrypted key was not read")
        }
        XCTAssertTrue(received == key); XCTAssertTrue(passphrase == "synthetic-sync-key-passphrase")
        let text = String(describing: defaults.dictionaryRepresentation())
        XCTAssertFalse(text.contains("OPENSSH PRIVATE KEY")); XCTAssertFalse(text.contains("synthetic-sync-key-passphrase"))
    }

    @MainActor
    func testControllerDoesNotTouchCredentialsWhenMetadataPublicationFails() async throws {
        let defaults = try self.defaults(); let (library, _, _) = library(defaults)
        let backend = CredentialBackend(); let transport = SyncTestTransport()
        let prepared = provider(backend, defaults)
        await transport.configure(publishFailure: .remoteConflict)
        let controller = DeviceLibrarySyncController(store: library, transportFactory: { transport }, credentialFactory: { _ in
            XCTFail("Metadata publication must succeed first"); return prepared
        })
        controller.selectStorage(.iCloud); await controller.synchronizeNow()
        XCTAssertEqual(controller.status, .failed(.conflict)); XCTAssertEqual(backend.cloudCalls, 0)
    }

    @MainActor
    func testControllerNeverEnablesCloudCredentialsForUnverifiedCurrentAccount() async throws {
        let defaults = try self.defaults(); let (library, _, _) = library(defaults)
        defaults.set("other-account", forKey: "com.aethernative.aetherscreens.sync.bound-account.v1")
        let backend = CredentialBackend(); let transport = SyncTestTransport()
        let prepared = provider(backend, defaults)
        let controller = DeviceLibrarySyncController(store: library, transportFactory: { transport }, credentialFactory: { account in
            XCTAssertEqual(account, "other-account", "Only local recovery for the prior bound owner is allowed")
            return prepared
        })
        controller.selectStorage(.iCloud); await controller.synchronizeNow()
        XCTAssertEqual(controller.status, .failed(.accountChanged)); XCTAssertEqual(backend.cloudCalls, 0)
    }

    @MainActor
    func testRestartedControllerUpdatesOldPendingSecretBeforeAcceptingOfflineEdit() async throws {
        let defaults = try self.defaults(); let (library, legacy, ssh) = library(defaults); let device = try device()
        library.addDevice(device); try library.selectStorage(.iCloud)
        defaults.set("test-account-A", forKey: "com.aethernative.aetherscreens.sync.bound-account.v1")
        let backend = CredentialBackend(); let prepared = provider(backend, defaults)
        library.installLocalCredentialProvider(prepared)
        library.updatePassword("synthetic-before-restart", for: device)
        let restarted = TestStorage.make(userDefaults: defaults, passwordStore: legacy, sshKeychain: SSHKeychainStore(backend: ssh))
        let transport = SyncTestTransport()
        let controller = DeviceLibrarySyncController(store: restarted, transportFactory: { transport }, credentialFactory: { _ in prepared })
        restarted.updatePassword("synthetic-after-restart", for: device)
        XCTAssertEqual(backend.cloudCalls, 0)
        await controller.synchronizeNow()
        XCTAssertEqual(controller.status, .synchronized)
        let second = provider(CredentialBackend(remote: backend.remote), try self.defaults()); second.setCloudAccess(true)
        XCTAssertEqual(try password(second, device), "synthetic-after-restart")
    }

    func testFailedLocalStagePreservesPreviousPendingValueForConnectionAndRetry() throws {
        let backend = CredentialBackend(); let store = provider(backend, try defaults()); let device = try device()
        try store.stagePassword("synthetic-preserved-pending", for: device)
        backend.failLocalWrites = true
        XCTAssertThrowsError(try store.stagePassword("synthetic-rejected-pending", for: device))
        XCTAssertEqual(try password(store, device), "synthetic-preserved-pending")
        backend.failLocalWrites = false; try flush(store, [device])
        XCTAssertEqual(try password(store, device), "synthetic-preserved-pending")
    }

    @MainActor
    func testControllerCredentialFailureDoesNotReportMetadataOnlySuccess() async throws {
        let defaults = try self.defaults(); let (library, legacy, _) = library(defaults); let device = try device()
        library.addDevice(device); legacy.values[device.id.uuidString] = "synthetic-bootstrap-failure"
        let backend = CredentialBackend(); backend.failCloudWrites = true
        let transport = SyncTestTransport()
        let prepared = provider(backend, defaults)
        let controller = DeviceLibrarySyncController(store: library, transportFactory: { transport }, credentialFactory: { _ in
            prepared
        })
        controller.selectStorage(.iCloud); await controller.synchronizeNow()
        XCTAssertEqual(controller.status, .failed(.credentials))
        let counts = await transport.counts(); XCTAssertEqual(counts.publish, 1)
        XCTAssertEqual(library.getPassword(for: device), "synthetic-bootstrap-failure")
        backend.failCloudWrites = false; await controller.synchronizeNow()
        XCTAssertEqual(controller.status, .synchronized)
    }

    @MainActor
    func testPasswordOnlyEditSchedulesCredentialSynchronization() async throws {
        let defaults = try self.defaults(); let (library, _, _) = library(defaults); let device = try device()
        library.addDevice(device)
        let backend = CredentialBackend(); let transport = SyncTestTransport()
        let prepared = provider(backend, defaults)
        let controller = DeviceLibrarySyncController(store: library, transportFactory: { transport }, credentialFactory: { _ in
            prepared
        }, debounceNanoseconds: 10_000_000)
        controller.selectStorage(.iCloud); await controller.synchronizeNow(); controller.resumeAutomaticSynchronization()
        library.updatePassword("synthetic-password-only-edit", for: device)
        for _ in 0..<100 {
            if !backend.remote.values.isEmpty, controller.status == .synchronized { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(backend.remote.values.isEmpty); XCTAssertEqual(controller.status, .synchronized)
        controller.suspendAutomaticSynchronization()
    }
}
