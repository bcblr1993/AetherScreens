import XCTest
import Combine
import Security
@testable import AetherScreensCore

final class ComputerSyncStoreTests: XCTestCase {
    func testOlderStoreCannotOverwriteAnotherStoresNewerCheckpoint() throws {
        let suiteA = "test.aetherscreens.sync-writer-A.\(UUID())"
        let suiteB = "test.aetherscreens.sync-writer-B.\(UUID())"
        let defaultsA = try XCTUnwrap(UserDefaults(suiteName: suiteA))
        let defaultsB = try XCTUnwrap(UserDefaults(suiteName: suiteB))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer {
            defaultsA.removePersistentDomain(forName: suiteA); defaultsB.removePersistentDomain(forName: suiteB)
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("checkpoint.json")
        let first = DeviceStore(userDefaults: defaultsA)
        var device = RemoteDevice(name: "Original", host: "local.invalid")
        try first.commitLocalSyncConfiguration([device], checkpointURL: url)
        let second = DeviceStore(userDefaults: defaultsB)
        XCTAssertTrue(try second.recoverSyncCheckpoint(at: url))
        let oldDevice = device
        device.name = "Newer"
        try first.commitLocalSyncConfiguration([device], checkpointURL: url)
        let bytes = try Data(contentsOf: url)
        let before = defaultsB.dictionaryRepresentation()
        XCTAssertThrowsError(try second.commitLocalSyncConfiguration([oldDevice], checkpointURL: url))
        XCTAssertEqual(second.devices, [oldDevice])
        XCTAssertEqual(defaultsB.dictionaryRepresentation() as NSDictionary, before as NSDictionary)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertTrue(try second.recoverSyncCheckpoint(at: url))
        XCTAssertEqual(second.devices, [device])
    }

    func testWrongAccountRecoveryPreservesCurrentStoreAndPreferences() throws {
        let suite = "test.aetherscreens.sync-account-recovery.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("checkpoint.json")
        let accountA = try ComputerSyncAccountScope(accountIdentifier: "generated-account-A")
        let accountB = try ComputerSyncAccountScope(accountIdentifier: "generated-account-B")
        let store = DeviceStore(userDefaults: defaults)
        let deviceA = RemoteDevice(name: "A", host: "a.invalid")
        try store.commitLocalSyncConfiguration([deviceA], checkpointURL: url, accountScope: accountA)
        let deviceB = RemoteDevice(name: "B", host: "b.invalid")
        store.addDevice(deviceB)
        let before = defaults.dictionaryRepresentation()
        XCTAssertThrowsError(try store.recoverSyncCheckpoint(at: url, accountScope: accountB))
        XCTAssertEqual(store.devices, [deviceA, deviceB])
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before as NSDictionary)
        XCTAssertTrue(try store.recoverSyncCheckpoint(at: url, accountScope: accountA))
        XCTAssertEqual(store.devices, [deviceA])
    }

    func testLocalConfigurationCommitsBeforePublicationAndFirstDeletionGetsTombstone() throws {
        let suite = "test.aetherscreens.sync-local-transaction.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let store = DeviceStore(userDefaults: defaults)
        let removed = RemoteDevice(name: "Remove", host: "remove.invalid")
        store.addDevice(removed)
        let added = RemoteDevice(name: "Add", host: "add.invalid")
        let before = defaults.dictionaryRepresentation()
        XCTAssertThrowsError(try store.commitLocalSyncConfiguration([added], checkpointURL: directory))
        XCTAssertEqual(store.devices, [removed])
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before as NSDictionary)
        let url = directory.appendingPathComponent("checkpoint.json")
        try store.commitLocalSyncConfiguration([added], checkpointURL: url)
        XCTAssertEqual(store.devices, [added])
        let checkpoint = try XCTUnwrap(ComputerSyncCheckpointFile(url: url).load())
        let journal = try ComputerSyncJournal(restoring: checkpoint.journal)
        XCTAssertNil(try XCTUnwrap(journal.records[removed.id]).metadata)
        XCTAssertEqual(checkpoint.credentialBindings["vnc:\(added.id.uuidString)"], "unbound")
        XCTAssertEqual(checkpoint.credentialBindings["ssh:\(added.id.uuidString)"], "unbound")
        let committedBytes = try Data(contentsOf: url)
        XCTAssertThrowsError(try store.commitLocalSyncConfiguration([added, added], checkpointURL: url))
        XCTAssertEqual(store.devices, [added])
        XCTAssertEqual(try Data(contentsOf: url), committedBytes)
        defaults.set(try JSONEncoder().encode([removed]), forKey: DeviceStore.storageKey)
        let recovered = DeviceStore(userDefaults: defaults)
        XCTAssertTrue(try recovered.recoverSyncCheckpoint(at: url))
        XCTAssertEqual(recovered.devices, [added])
        XCTAssertEqual(try recovered.captureLocalSyncJournal().records, journal.records)
    }

    func testLocalEditAndDeletionCaptureReplaceDurableCheckpointBeforeRecovery() throws {
        let suite = "test.aetherscreens.sync-local-checkpoint.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("checkpoint.json")
        let store = DeviceStore(userDefaults: defaults)
        var edited = RemoteDevice(name: "Local", host: "local.invalid")
        let removed = RemoteDevice(name: "Remove", host: "remove.invalid")
        store.addDevice(edited); store.addDevice(removed)
        let initial = try store.captureLocalSyncJournal(checkpointURL: url)
        edited.name = "Edited"
        store.updateDevice(edited)
        XCTAssertTrue(store.deleteDevice(removed))
        let final = try store.captureLocalSyncJournal(checkpointURL: url)
        XCTAssertEqual(initial.peer, final.peer)
        XCTAssertGreaterThan(final.counter, initial.counter)
        XCTAssertNil(try XCTUnwrap(final.records[removed.id]).metadata)
        edited.lastConnected = Date(timeIntervalSince1970: 1_700_000_000)
        store.updateDevice(edited)
        let runtimeOnly = try store.captureLocalSyncJournal(checkpointURL: url)
        XCTAssertEqual(runtimeOnly.counter, final.counter)
        XCTAssertEqual(runtimeOnly.records, final.records)
        defaults.set(try JSONEncoder().encode([removed]), forKey: DeviceStore.storageKey)
        defaults.set(try initial.encoded(), forKey: DeviceStore.syncJournalStorageKey)
        let recovered = DeviceStore(userDefaults: defaults)
        XCTAssertTrue(try recovered.recoverSyncCheckpoint(at: url))
        XCTAssertEqual(recovered.devices, [edited])
        XCTAssertEqual(try recovered.captureLocalSyncJournal().records, final.records)
        let bytes = try Data(contentsOf: url)
        XCTAssertThrowsError(try recovered.captureLocalSyncJournal(checkpointURL: directory))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(try recovered.captureLocalSyncJournal().records, final.records)
    }

    func testDurableMergeReplaysWholeCheckpointAfterPreferenceMirrorLoss() throws {
        let suite = "test.aetherscreens.sync-durable.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("checkpoint.json")
        let store = DeviceStore(userDefaults: defaults)
        let local = RemoteDevice(name: "Local", host: "local.invalid")
        let remoteDevice = RemoteDevice(name: "Remote", host: "remote.invalid")
        store.addDevice(local)
        var remote = ComputerSyncJournal()
        try remote.captureLocalComputers([remoteDevice])
        XCTAssertTrue(try store.mergeSyncSnapshot(remote.encoded(), checkpointURL: url).didChangeRecords)
        let checkpoint = try XCTUnwrap(ComputerSyncCheckpointFile(url: url).load())
        XCTAssertEqual(checkpoint.devices, store.devices)
        defaults.set(try JSONEncoder().encode([RemoteDevice]()), forKey: DeviceStore.storageKey)
        defaults.set(Data([1]), forKey: DeviceStore.syncJournalStorageKey)
        defaults.set([String: String](), forKey: "com.aethernative.aetherscreens.credential-targets")
        let recovered = DeviceStore(userDefaults: defaults)
        XCTAssertTrue(try recovered.recoverSyncCheckpoint(at: url))
        XCTAssertEqual(recovered.devices, checkpoint.devices)
        XCTAssertEqual(defaults.data(forKey: DeviceStore.syncJournalStorageKey), checkpoint.journal)
        XCTAssertEqual(defaults.dictionary(forKey: "com.aethernative.aetherscreens.credential-targets") as? [String: String], checkpoint.credentialBindings)
        XCTAssertTrue(try recovered.recoverSyncCheckpoint(at: url))
        XCTAssertEqual(try recovered.captureLocalSyncJournal().records,
                       try ComputerSyncJournal(restoring: checkpoint.journal).records)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testCheckpointWriteFailureDoesNotPublishMergedConfiguration() throws {
        let suite = "test.aetherscreens.sync-durable-failure.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let store = DeviceStore(userDefaults: defaults)
        let local = RemoteDevice(name: "Local", host: "local.invalid")
        store.addDevice(local)
        _ = try store.captureLocalSyncJournal()
        let before = defaults.dictionaryRepresentation()
        var remote = ComputerSyncJournal()
        try remote.captureLocalComputers([RemoteDevice(name: "Remote", host: "remote.invalid")])
        XCTAssertThrowsError(try store.mergeSyncSnapshot(remote.encoded(), checkpointURL: directory))
        XCTAssertEqual(store.devices, [local])
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before as NSDictionary)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { !$0.hasPrefix(".sync-lock-") }.isEmpty)
    }

    func testInvalidBindingsRejectMergeBeforePersistingPendingRecovery() throws {
        let suite = "test.aetherscreens.sync-preflight.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DeviceStore(userDefaults: defaults)
        let device = RemoteDevice(name: "Saved", host: "saved.invalid")
        store.addDevice(device)
        _ = try store.captureLocalSyncJournal()
        let bindingsKey = "com.aethernative.aetherscreens.credential-targets"
        let bindings = ["vnc:\(device.id.uuidString)": "invalid-target-token"]
        defaults.set(bindings, forKey: bindingsKey)
        let listBefore = defaults.data(forKey: DeviceStore.storageKey)
        let journalBefore = defaults.data(forKey: DeviceStore.syncJournalStorageKey)
        var remote = ComputerSyncJournal()
        var changed = device
        changed.host = "replacement.invalid"
        try remote.captureLocalComputers([changed])
        XCTAssertThrowsError(try store.mergeSyncSnapshot(remote.encoded()))
        XCTAssertEqual(store.devices, [device])
        XCTAssertEqual(defaults.data(forKey: DeviceStore.storageKey), listBefore)
        XCTAssertEqual(defaults.data(forKey: DeviceStore.syncJournalStorageKey), journalBefore)
        XCTAssertEqual(defaults.dictionary(forKey: bindingsKey) as? [String: String], bindings)
        XCTAssertNil(defaults.data(forKey: DeviceStore.pendingSyncJournalStorageKey))
        XCTAssertEqual(DeviceStore(userDefaults: defaults).devices, [device])
    }

    @MainActor
    func testReloadSkipsUnchangedListButPublishesMetadataAndConnectionChanges() throws {
        let suite = "test.aetherscreens.reload-list.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DeviceStore(userDefaults: defaults)
        var device = RemoteDevice(name: "Saved", host: "saved.invalid")
        store.addDevice(device)
        let model = DeviceListViewModel(store: store)
        var updates: [[RemoteDevice]] = []
        let subscription = model.$devices.dropFirst().sink { updates.append($0) }
        defer { subscription.cancel() }

        model.reload()
        model.reload()
        XCTAssertTrue(updates.isEmpty)

        device.name = "Renamed"
        store.addDevice(device)
        model.reload()
        XCTAssertEqual(updates, [[device]])
        let renamedDevice = device
        device.lastConnected = Date(timeIntervalSince1970: 1_700_000_000)
        store.addDevice(device)
        model.reload()
        XCTAssertEqual(updates, [[renamedDevice], [device]])
        model.reload()
        XCTAssertEqual(updates.count, 2)

        XCTAssertTrue(store.deleteDevice(device))
        model.reload()
        XCTAssertEqual(updates.count, 3)
        XCTAssertEqual(updates.last, [])
    }

    @MainActor
    func testMergedSnapshotPublishesOnceAndEchoDoesNotRefreshList() throws {
        let suite = "test.aetherscreens.sync-merge-list.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DeviceStore(userDefaults: defaults)
        let model = DeviceListViewModel(store: store)
        var count = 0
        let subscription = model.$devices.dropFirst().sink { _ in count += 1 }
        defer { subscription.cancel() }
        let device = RemoteDevice(name: "Remote", host: "remote.invalid")
        var remote = ComputerSyncJournal()
        try remote.captureLocalComputers([device])
        XCTAssertTrue(try model.mergeSyncSnapshot(remote.encoded()).didChangeRecords)
        XCTAssertEqual(count, 1)
        let echo = try store.captureLocalSyncJournal().encoded()
        XCTAssertFalse(try model.mergeSyncSnapshot(echo).didChangeRecords)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(model.devices.map(\.id), [device.id])
    }

    func testRemoteMergeCapturesLocalEditsAndPersistsMergedJournal() throws {
        let suite = "test.aetherscreens.sync-merge.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DeviceStore(userDefaults: defaults)
        let local = RemoteDevice(name: "Local", host: "local.invalid")
        let remoteDevice = RemoteDevice(name: "Remote", host: "remote.invalid")
        store.addDevice(local)
        var remote = ComputerSyncJournal()
        try remote.captureLocalComputers([remoteDevice])
        let result = try store.mergeSyncSnapshot(remote.encoded())
        XCTAssertTrue(result.didChangeRecords)
        XCTAssertTrue(result.remoteNeedsUpdate)
        XCTAssertEqual(Set(store.devices.map(\.id)), Set([local.id, remoteDevice.id]))
        let merged = try store.captureLocalSyncJournal()
        XCTAssertEqual(Set(merged.computers.map(\.id)), Set([local.id, remoteDevice.id]))
        XCTAssertNil(defaults.data(forKey: DeviceStore.pendingSyncJournalStorageKey))
        let relaunched = DeviceStore(userDefaults: defaults)
        XCTAssertEqual(try relaunched.captureLocalSyncJournal().records, merged.records)
    }

    func testPendingMergeRecoveryRunsBeforeLocalDeletionCapture() throws {
        let suite = "test.aetherscreens.sync-recovery.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let device = RemoteDevice(name: "Pending remote", host: "pending.invalid")
        var pending = ComputerSyncJournal()
        try pending.captureLocalComputers([device])
        defaults.set(try pending.encoded(), forKey: DeviceStore.pendingSyncJournalStorageKey)
        let recovered = DeviceStore(userDefaults: defaults)
        XCTAssertEqual(recovered.devices.map(\.id), [device.id])
        let captured = try recovered.captureLocalSyncJournal()
        XCTAssertEqual(captured.records, pending.records)
        XCTAssertEqual(captured.counter, pending.counter)
        XCTAssertNil(defaults.data(forKey: DeviceStore.pendingSyncJournalStorageKey))
    }

    func testMalformedRemoteOrPendingSnapshotPreservesLocalListAndJournal() throws {
        let suite = "test.aetherscreens.sync-malformed.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DeviceStore(userDefaults: defaults)
        let device = RemoteDevice(name: "Saved", host: "saved.invalid")
        store.addDevice(device)
        _ = try store.captureLocalSyncJournal()
        let journalBefore = defaults.data(forKey: DeviceStore.syncJournalStorageKey)
        let listBefore = defaults.data(forKey: DeviceStore.storageKey)
        XCTAssertThrowsError(try store.mergeSyncSnapshot(Data([0])))
        XCTAssertEqual(defaults.data(forKey: DeviceStore.syncJournalStorageKey), journalBefore)
        XCTAssertEqual(defaults.data(forKey: DeviceStore.storageKey), listBefore)
        defaults.set(Data([1]), forKey: DeviceStore.pendingSyncJournalStorageKey)
        let recovered = DeviceStore(userDefaults: defaults)
        XCTAssertEqual(recovered.devices, [device])
        XCTAssertThrowsError(try recovered.captureLocalSyncJournal())
        XCTAssertEqual(defaults.data(forKey: DeviceStore.pendingSyncJournalStorageKey), Data([1]))
        XCTAssertEqual(defaults.data(forKey: DeviceStore.syncJournalStorageKey), journalBefore)
    }

    func testLocalCapturePersistsIdentityAndDeletionAndDoesNotOverwriteCorruption() throws {
        let suite = "test.aetherscreens.sync-capture.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DeviceStore(userDefaults: defaults)
        let device = RemoteDevice(name: "Local", host: "local.invalid")
        store.addDevice(device)
        let initial = try store.captureLocalSyncJournal()
        let persisted = defaults.data(forKey: DeviceStore.syncJournalStorageKey)
        let restored = DeviceStore(userDefaults: defaults)
        let repeated = try restored.captureLocalSyncJournal()
        XCTAssertEqual(repeated.peer, initial.peer)
        XCTAssertEqual(repeated.counter, initial.counter)
        XCTAssertEqual(defaults.data(forKey: DeviceStore.syncJournalStorageKey), persisted)
        XCTAssertTrue(restored.deleteDevice(device))
        let removed = try restored.captureLocalSyncJournal()
        XCTAssertEqual(removed.peer, initial.peer)
        XCTAssertNil(try XCTUnwrap(removed.records[device.id]).metadata)
        defaults.set(Data([0, 1, 2]), forKey: DeviceStore.syncJournalStorageKey)
        XCTAssertThrowsError(try restored.captureLocalSyncJournal())
        XCTAssertEqual(defaults.data(forKey: DeviceStore.syncJournalStorageKey), Data([0, 1, 2]))
    }

    private final class PasswordAccess: SSHKeychainAccess {
        var reads = 0
        func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus { errSecSuccess }
        func add(_ attributes: [String: Any]) -> OSStatus { errSecSuccess }
        func delete(_ query: [String: Any]) -> OSStatus { errSecSuccess }
        func accounts(_ query: [String: Any]) -> (OSStatus, [String]?) { (errSecItemNotFound, nil) }
        func copy(_ query: [String: Any]) -> (OSStatus, Data?) {
            reads += 1
            return (errSecSuccess, Data([1, 2, 3]))
        }
    }

    func testSSHChangedTargetDoesNotReadVaultUntilExplicitlyRebound() throws {
        let suite = "test.aetherscreens.sync-ssh-binding.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let access = PasswordAccess()
        let vault = SSHCredentialStore(service: suite, access: access)
        let store = DeviceStore(userDefaults: defaults, sshCredentials: vault)
        var device = RemoteDevice(name: "SSH", host: "desktop.invalid")
        device.ssh = try XCTUnwrap(SSHConnectionSettings(
            server: XCTUnwrap(SSHServerAddress(host: "ssh.invalid")), username: "first"))
        store.addDevice(device)
        XCTAssertNotNil(try store.getSSHPassword(for: device))
        var changed = device
        changed.ssh = try XCTUnwrap(SSHConnectionSettings(
            server: XCTUnwrap(SSHServerAddress(host: "ssh.invalid")), username: "second"))
        var journal = ComputerSyncJournal()
        try journal.upsert(.init(device: changed))
        try store.applySyncJournal(journal)
        XCTAssertNil(try store.getSSHPassword(for: changed))
        XCTAssertEqual(access.reads, 1)
        store.bindSavedSSHPassword(for: changed)
        XCTAssertNotNil(try store.getSSHPassword(for: changed))
        XCTAssertEqual(access.reads, 2)
        XCTAssertNil(try store.getSSHPassword(for: device))
    }

    @MainActor
    func testListPublishesOnceAndRemoteDeletionLeavesActiveSessionSelectionIntact() throws {
        let suite = "test.aetherscreens.sync-list.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DeviceStore(userDefaults: defaults)
        let device = RemoteDevice(name: "Active", host: "active.invalid")
        store.addDevice(device)
        let model = DeviceListViewModel(store: store)
        model.activeSessionDevice = device
        var updates: [[RemoteDevice]] = []
        let subscription = model.$devices.dropFirst().sink { updates.append($0) }
        defer { subscription.cancel() }
        var journal = ComputerSyncJournal()
        try journal.delete(device.id)
        XCTAssertTrue(try model.applySyncJournal(journal))
        XCTAssertEqual(updates, [[]])
        XCTAssertTrue(model.devices.isEmpty)
        XCTAssertEqual(model.activeSessionDevice, device)
        XCTAssertFalse(try model.applySyncJournal(journal))
        XCTAssertEqual(updates.count, 1)
    }

    func testMergedConfigurationPreservesLocalRuntimeAndUnmentionedDevices() throws {
        let suite = "test.aetherscreens.sync-store.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DeviceStore(userDefaults: defaults)
        let connected = RemoteDevice(name: "Local", host: "local.invalid", isOnline: true,
                                     lastConnected: Date(timeIntervalSince1970: 123))
        let untouched = RemoteDevice(name: "Unmentioned", host: "untouched.invalid")
        store.addDevice(connected)
        store.addDevice(untouched)
        var updated = connected
        updated.name = "Remote edit"
        updated.isOnline = false
        updated.lastConnected = nil
        let added = RemoteDevice(name: "New remote", host: "new.invalid", isOnline: true)
        var journal = ComputerSyncJournal()
        try journal.upsert(.init(device: updated))
        try journal.upsert(.init(device: added))
        XCTAssertTrue(try store.applySyncJournal(journal))
        let actual = try XCTUnwrap(store.devices.first { $0.id == connected.id })
        XCTAssertEqual(actual.name, updated.name)
        XCTAssertEqual(actual.host, updated.host)
        XCTAssertTrue(actual.isOnline)
        XCTAssertEqual(actual.lastConnected, connected.lastConnected)
        XCTAssertTrue(store.devices.contains(untouched))
        XCTAssertFalse(try XCTUnwrap(store.devices.first { $0.id == added.id }).isOnline)
        XCTAssertFalse(try store.applySyncJournal(journal))
        XCTAssertEqual(DeviceStore(userDefaults: defaults).devices, store.devices)
    }

    func testEndpointChangeAppliesButOldPasswordIsBoundToOriginalTarget() throws {
        let suite = "test.aetherscreens.sync-rebind.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = KeychainStore(serviceName: suite, legacyServiceName: nil)
        let store = DeviceStore(userDefaults: defaults, keychain: keychain)
        let device = RemoteDevice(name: "Original", host: "original.invalid")
        let originalPassword = UUID().uuidString
        defer { keychain.deletePassword(forKey: device.id.uuidString) }
        store.addDevice(device, password: originalPassword)
        var changed = device
        changed.host = "substituted.invalid"
        var journal = ComputerSyncJournal()
        try journal.upsert(.init(device: changed))
        XCTAssertTrue(try store.applySyncJournal(journal))
        XCTAssertEqual(store.devices, [changed])
        XCTAssertNil(store.getPassword(for: changed))
        XCTAssertEqual(store.getPassword(for: device), originalPassword)
        let relaunched = DeviceStore(userDefaults: defaults, keychain: keychain)
        XCTAssertNil(relaunched.getPassword(for: changed))
        let newPassword = UUID().uuidString
        relaunched.updatePassword(newPassword, for: changed)
        XCTAssertEqual(relaunched.getPassword(for: changed), newPassword)
        XCTAssertNil(relaunched.getPassword(for: device))
        var renamed = changed
        renamed.name = "Renamed"
        XCTAssertEqual(relaunched.getPassword(for: renamed), newPassword)
    }

    func testRemoteDeletionPersistsAndReapplyingCannotRestoreRecord() throws {
        let suite = "test.aetherscreens.sync-delete.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DeviceStore(userDefaults: defaults)
        let device = RemoteDevice(name: "Deleted", host: "delete.invalid")
        store.addDevice(device)
        var journal = ComputerSyncJournal()
        try journal.upsert(.init(device: device))
        var stale = journal
        try journal.delete(device.id)
        try stale.merge(journal.encoded())
        XCTAssertTrue(try store.applySyncJournal(stale))
        XCTAssertTrue(store.devices.isEmpty)
        XCTAssertFalse(try store.applySyncJournal(stale))
        XCTAssertTrue(DeviceStore(userDefaults: defaults).devices.isEmpty)
    }

    func testNewRemoteComputerCannotInheritOrphanedLegacyPassword() throws {
        let suite = "test.aetherscreens.sync-orphan.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = KeychainStore(serviceName: suite, legacyServiceName: nil)
        let device = RemoteDevice(name: "Remote", host: "remote.invalid")
        keychain.savePassword(UUID().uuidString, forKey: device.id.uuidString)
        defer { keychain.deletePassword(forKey: device.id.uuidString) }
        let store = DeviceStore(userDefaults: defaults, keychain: keychain)
        var journal = ComputerSyncJournal()
        try journal.upsert(.init(device: device))
        try store.applySyncJournal(journal)
        XCTAssertNil(store.getPassword(for: device))
        XCTAssertNil(DeviceStore(userDefaults: defaults, keychain: keychain).getPassword(for: device))
    }
}
