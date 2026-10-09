import XCTest
@testable import AetherScreensCore

final class ComputerSyncCoordinatorTests: XCTestCase {
    func testRemoteUpdateRejectsStaleEditorButEchoPreservesCurrentRevision() async throws {
        let suite = "test.aetherscreens.coordinator-editor.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let coordinator = try ComputerSyncCoordinator(store: DeviceStore(userDefaults: defaults),
            accountIdentifier: "generated-editor-account", rootDirectory: root)
        try await coordinator.activate()
        let device = RemoteDevice(name: "Original", host: "original.invalid")
        try await save([device], using: coordinator)
        let editor = try await coordinator.librarySnapshot()
        var remote = try ComputerSyncJournal(restoring: await coordinator.exportSnapshot())
        var renamed = device
        renamed.name = "Remote rename"
        try remote.upsert(ComputerSyncMetadata(device: renamed))
        _ = try await coordinator.mergeRemoteSnapshot(remote.encoded())
        do {
            try await coordinator.saveConfiguration(editor.computers, basedOn: editor.revision)
            XCTFail("Stale editor must not overwrite remote changes")
        } catch ComputerSyncCoordinator.Failure.libraryChanged {}
        let current = try await coordinator.librarySnapshot()
        XCTAssertEqual(current.computers, [renamed])
        XCTAssertNotEqual(current.revision, editor.revision)
        let echo = try await coordinator.exportSnapshot()
        _ = try await coordinator.mergeRemoteSnapshot(echo)
        let afterEcho = try await coordinator.librarySnapshot()
        XCTAssertEqual(afterEcho.revision, current.revision)
        try await coordinator.saveConfiguration(current.computers, basedOn: current.revision)
    }

    private func save(_ computers: [RemoteDevice], using coordinator: ComputerSyncCoordinator) async throws {
        let snapshot = try await coordinator.librarySnapshot()
        try await coordinator.saveConfiguration(computers, basedOn: snapshot.revision)
    }

    func testCorruptCheckpointPreventsActivationWithoutResettingStoredLibrary() async throws {
        let suite = "test.aetherscreens.coordinator-corrupt.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let account = "generated-corrupt-account"
        let original = try ComputerSyncCoordinator(store: DeviceStore(userDefaults: defaults),
            accountIdentifier: account, rootDirectory: root)
        try await original.activate()
        let device = RemoteDevice(name: "Keep", host: "keep.invalid")
        try await save([device], using: original)
        let scope = try ComputerSyncAccountScope(accountIdentifier: account)
        let url = root.appendingPathComponent(scope.digest).appendingPathComponent("checkpoint.json")
        let corrupt = Data([1, 2, 3])
        try corrupt.write(to: url)
        let store = DeviceStore(userDefaults: defaults)
        let relaunched = try ComputerSyncCoordinator(store: store, accountIdentifier: account, rootDirectory: root)
        do { try await relaunched.activate(); XCTFail("Corrupt checkpoint must block activation") }
        catch {}
        do { _ = try await relaunched.computers(); XCTFail("Failed activation must not allow access") }
        catch ComputerSyncCoordinator.Failure.notActivated {}
        XCTAssertEqual(store.devices, [device])
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }

    func testActivationRecoveryEditingAndMetadataExport() async throws {
        let suite = "test.aetherscreens.coordinator.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let coordinator = try ComputerSyncCoordinator(store: DeviceStore(userDefaults: defaults),
            accountIdentifier: "generated-account", rootDirectory: root)
        do { _ = try await coordinator.computers(); XCTFail("Activation must precede access") }
        catch ComputerSyncCoordinator.Failure.notActivated {}
        try await coordinator.activate()
        var device = RemoteDevice(name: "Generated", host: "generated.invalid")
        device.lastConnected = Date(timeIntervalSince1970: 1_700_000_000)
        try await save([device], using: coordinator)
        let exported = try await coordinator.exportSnapshot()
        let text = String(decoding: exported, as: UTF8.self)
        XCTAssertFalse(text.contains("lastConnected"))
        XCTAssertFalse(text.contains("credentialBindings"))
        XCTAssertFalse(text.contains("accountScopeDigest"))
        let journal = try ComputerSyncJournal(restoring: exported)
        XCTAssertEqual(journal.computers.map(\.name), ["Generated"])
        defaults.set(try JSONEncoder().encode([RemoteDevice]()), forKey: DeviceStore.storageKey)
        let relaunched = try ComputerSyncCoordinator(store: DeviceStore(userDefaults: defaults),
            accountIdentifier: "generated-account", rootDirectory: root)
        try await relaunched.activate()
        let recovered = try await relaunched.computers()
        XCTAssertEqual(recovered, [device])
        try await save([], using: relaunched)
        let deleted = try ComputerSyncJournal(restoring: await relaunched.exportSnapshot())
        XCTAssertNil(try XCTUnwrap(deleted.records[device.id]).metadata)
    }

    func testSeparateAccountDirectoriesDoNotShareLibraries() async throws {
        let suiteA = "test.aetherscreens.coordinator-A.\(UUID())"
        let suiteB = "test.aetherscreens.coordinator-B.\(UUID())"
        let defaultsA = try XCTUnwrap(UserDefaults(suiteName: suiteA))
        let defaultsB = try XCTUnwrap(UserDefaults(suiteName: suiteB))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            defaultsA.removePersistentDomain(forName: suiteA); defaultsB.removePersistentDomain(forName: suiteB)
            try? FileManager.default.removeItem(at: root)
        }
        let first = try ComputerSyncCoordinator(store: DeviceStore(userDefaults: defaultsA),
            accountIdentifier: "generated-A", rootDirectory: root)
        let second = try ComputerSyncCoordinator(store: DeviceStore(userDefaults: defaultsB),
            accountIdentifier: "generated-B", rootDirectory: root)
        try await first.activate(); try await second.activate()
        let device = RemoteDevice(name: "A", host: "a.invalid")
        try await save([device], using: first)
        let secondList = try await second.computers()
        XCTAssertTrue(secondList.isEmpty)
        try await second.activate()
        let firstList = try await first.computers()
        XCTAssertEqual(firstList, [device])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 2)
    }
}
