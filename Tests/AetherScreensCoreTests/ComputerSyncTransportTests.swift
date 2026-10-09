import XCTest
@testable import AetherScreensCore

final class ComputerSyncTransportTests: XCTestCase {
    func testConflictRefetchMergesBothLibrariesBeforeRetry() async throws {
        let suite = "test.aetherscreens.transport.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let coordinator = try ComputerSyncCoordinator(store: DeviceStore(userDefaults: defaults), accountIdentifier: "generated", rootDirectory: root)
        try await coordinator.activate()
        let local = RemoteDevice(name: "Local", host: "local.invalid")
        let revision = try await coordinator.librarySnapshot().revision
        try await coordinator.saveConfiguration([local], basedOn: revision)
        var remote = ComputerSyncJournal()
        let other = RemoteDevice(name: "Remote", host: "remote.invalid")
        try remote.upsert(ComputerSyncMetadata(device: other))
        let transport = Stub(account: "generated", conflictingJournal: try remote.encoded())
        try await coordinator.synchronize(using: transport)
        let computers = try await coordinator.computers()
        XCTAssertEqual(Set(computers.map(\.id)), Set([local.id, other.id]))
        let saved = await transport.saved
        XCTAssertEqual(saved.count, 2)
        XCTAssertNil(saved[0].1)
        XCTAssertEqual(saved[1].1, "remote-version")
        XCTAssertEqual(try ComputerSyncJournal(restoring: saved[1].0).computers.count, 2)
    }

    func testWrongAccountDoesNotMergeOrUpload() async throws {
        let suite = "test.aetherscreens.transport-account.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let coordinator = try ComputerSyncCoordinator(store: DeviceStore(userDefaults: defaults), accountIdentifier: "expected", rootDirectory: root)
        try await coordinator.activate()
        let before = try await coordinator.exportSnapshot()
        let transport = Stub(account: "other", conflictingJournal: try ComputerSyncJournal().encoded())
        do { try await coordinator.synchronize(using: transport); XCTFail("Wrong account must fail") }
        catch CloudKitComputerSyncReader.Failure.accountChanged {}
        let after = try await coordinator.exportSnapshot()
        let saved = await transport.saved
        XCTAssertEqual(before, after)
        XCTAssertTrue(saved.isEmpty)
    }

    func testRepeatedConflictsStopAfterThreeAttemptsAndKeepLocalConfiguration() async throws {
        let suite = "test.aetherscreens.transport-limit.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let coordinator = try ComputerSyncCoordinator(store: DeviceStore(userDefaults: defaults), accountIdentifier: "generated", rootDirectory: root)
        try await coordinator.activate()
        let device = RemoteDevice(name: "Keep", host: "keep.invalid")
        let revision = try await coordinator.librarySnapshot().revision
        try await coordinator.saveConfiguration([device], basedOn: revision)
        let transport = Stub(account: "generated", conflictingJournal: try ComputerSyncJournal().encoded(), alwaysConflict: true)
        do { try await coordinator.synchronize(using: transport); XCTFail("Repeated conflicts must terminate") }
        catch ComputerSyncCoordinator.Failure.retryLimit {}
        let attempts = await transport.saved.count
        let computers = try await coordinator.computers()
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(computers, [device])
    }

    func testEditDuringUploadIsIncludedInNextAttempt() async throws {
        let suite = "test.aetherscreens.transport-edit.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let coordinator = try ComputerSyncCoordinator(store: DeviceStore(userDefaults: defaults), accountIdentifier: "generated", rootDirectory: root)
        try await coordinator.activate()
        let original = RemoteDevice(name: "Before", host: "edit.invalid")
        let revision = try await coordinator.librarySnapshot().revision
        try await coordinator.saveConfiguration([original], basedOn: revision)
        var edited = original
        edited.name = "During upload"
        let replacement = edited
        let initial = try await coordinator.exportSnapshot()
        let transport = Stub(account: "generated", conflictingJournal: initial, conflictFirst: false) { attempt in
            guard attempt == 1 else { return }
            let competing = Stub(account: "generated", conflictingJournal: initial)
            do { try await coordinator.synchronize(using: competing); XCTFail("Overlapping sync must fail") }
            catch ComputerSyncCoordinator.Failure.synchronizationInProgress {}
            let current = try await coordinator.librarySnapshot()
            try await coordinator.saveConfiguration([replacement], basedOn: current.revision)
        }
        try await coordinator.synchronize(using: transport)
        let saved = await transport.saved
        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(try ComputerSyncJournal(restoring: saved[0].0).computers.map(\.name), ["Before"])
        XCTAssertEqual(try ComputerSyncJournal(restoring: saved[1].0).computers.map(\.name), ["During upload"])
    }

    private actor Stub: ComputerSyncTransport {
        let account: String
        let conflictingJournal: Data
        var saved: [(Data, String?)] = []
        let alwaysConflict: Bool
        let conflictFirst: Bool
        let onSave: (@Sendable (Int) async throws -> Void)?
        init(account: String, conflictingJournal: Data, alwaysConflict: Bool = false, conflictFirst: Bool = true,
             onSave: (@Sendable (Int) async throws -> Void)? = nil) {
            self.account = account; self.conflictingJournal = conflictingJournal
            self.alwaysConflict = alwaysConflict; self.conflictFirst = conflictFirst; self.onSave = onSave
        }
        func fetch() async throws -> CloudKitComputerSyncReader.Read {
            .init(accountIdentifier: account, snapshot: saved.isEmpty ? nil : .init(journal: conflictingJournal, changeTag: "remote-version"))
        }
        func save(journal: Data, accountIdentifier: String, expectedChangeTag: String?) async throws -> CloudKitComputerSyncReader.Read {
            saved.append((journal, expectedChangeTag))
            try await onSave?(saved.count)
            if alwaysConflict || (conflictFirst && saved.count == 1) { throw CloudKitComputerSyncReader.Failure.versionConflict }
            return .init(accountIdentifier: account, snapshot: .init(journal: journal, changeTag: "saved-version"))
        }
    }
}
