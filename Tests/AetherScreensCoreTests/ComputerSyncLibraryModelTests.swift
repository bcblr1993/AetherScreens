import XCTest
@testable import AetherScreensCore

final class ComputerSyncLibraryModelTests: XCTestCase {
    @MainActor
    func testOlderSyncSnapshotCannotOverwriteNewerSavedSnapshot() async throws {
        let held = expectation(description: "Old snapshot captured")
        let session = SnapshotRaceSession(held: { held.fulfill() })
        let model = ComputerSyncLibraryModel()
        await model.select(session)
        let revision = try XCTUnwrap(model.snapshot).revision
        let syncing = Task { await model.synchronize(using: UnusedTransport()) }
        await fulfillment(of: [held], timeout: 3)
        let saved = await model.save([RemoteDevice(name: "New edit", host: "edit.invalid")], basedOn: revision)
        XCTAssertTrue(saved)
        XCTAssertEqual(model.snapshot?.computers.map(\.name), ["New edit"])
        await session.release()
        let synced = await syncing.value
        XCTAssertTrue(synced)
        XCTAssertEqual(model.snapshot?.computers.map(\.name), ["New edit"])
        XCTAssertFalse(model.isSaving)
        XCTAssertFalse(model.isSynchronizing)
    }

    @MainActor
    func testSyncRefreshesDurableSnapshotEvenWhenUploadFails() async throws {
        for fails in [false, true] {
            let model = ComputerSyncLibraryModel()
            await model.select(SyncLibrarySession(fails: fails))
            let result = await model.synchronize(using: UnusedTransport())
            XCTAssertEqual(result, !fails)
            XCTAssertEqual(model.snapshot?.computers.map(\.name), ["Merged"])
            XCTAssertEqual(model.failure, fails ? .syncFailed : nil)
            XCTAssertFalse(model.isSynchronizing)
        }
    }

    @MainActor
    func testOldSyncCompletionCannotUpdateNewAccount() async throws {
        let held = expectation(description: "Sync held")
        let old = SyncLibrarySession(fails: true, held: { held.fulfill() })
        let model = ComputerSyncLibraryModel()
        await model.select(old)
        let syncing = Task { await model.synchronize(using: UnusedTransport()) }
        await fulfillment(of: [held], timeout: 3)
        XCTAssertTrue(model.isSynchronizing)
        let duplicate = await model.synchronize(using: UnusedTransport())
        XCTAssertFalse(duplicate)
        await model.select(HeldLibrarySession(name: "Current"))
        await old.release()
        let result = await syncing.value
        XCTAssertFalse(result)
        XCTAssertEqual(model.snapshot?.computers.map(\.name), ["Current"])
        XCTAssertNil(model.failure)
        XCTAssertFalse(model.isSynchronizing)
    }

    @MainActor
    func testEditorConflictKeepsDisplayedSnapshotAndReturnsFailure() async throws {
        let model = ComputerSyncLibraryModel()
        await model.select(HeldLibrarySession(name: "Current"))
        let snapshot = try XCTUnwrap(model.snapshot)
        let saved = await model.save([RemoteDevice(name: "Draft", host: "draft.invalid")], basedOn: snapshot.revision)
        XCTAssertFalse(saved)
        XCTAssertEqual(model.failure, .libraryChanged)
        XCTAssertEqual(model.snapshot?.revision, snapshot.revision)
        XCTAssertEqual(model.snapshot?.computers, snapshot.computers)
        XCTAssertFalse(model.isSaving)
    }

    @MainActor
    func testOldAccountActivationCannotReplaceNewAccountAfterSwitch() async throws {
        let held = expectation(description: "Old account activation held")
        let old = HeldLibrarySession(name: "Old", held: { held.fulfill() })
        let current = HeldLibrarySession(name: "Current")
        let model = ComputerSyncLibraryModel()
        let loading = Task { await model.select(old) }
        await fulfillment(of: [held], timeout: 3)
        XCTAssertTrue(model.isLoading)
        await model.select(current)
        XCTAssertEqual(model.snapshot?.computers.map(\.name), ["Current"])
        await old.release()
        await loading.value
        XCTAssertEqual(model.snapshot?.computers.map(\.name), ["Current"])
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.failure)
    }

    @MainActor
    func testDeselectionPreventsLateActivationFromRestoringAccount() async throws {
        let held = expectation(description: "Activation held")
        let old = HeldLibrarySession(name: "Old", held: { held.fulfill() })
        let model = ComputerSyncLibraryModel()
        let loading = Task { await model.select(old) }
        await fulfillment(of: [held], timeout: 3)
        model.deselect()
        await old.release()
        await loading.value
        XCTAssertNil(model.snapshot)
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.failure)
    }
}

private actor SnapshotRaceSession: ComputerSyncLibrarySession {
    private var snapshot = ComputerSyncCoordinator.LibrarySnapshot(revision: UUID(), computers: [])
    private var reads = 0
    private let held: @Sendable () -> Void
    private var continuation: CheckedContinuation<Void, Never>?
    init(held: @escaping @Sendable () -> Void) { self.held = held }
    func activate() async throws {}
    func librarySnapshot() async -> ComputerSyncCoordinator.LibrarySnapshot {
        reads += 1
        let captured = snapshot
        if reads == 2 {
            await withCheckedContinuation { continuation in self.continuation = continuation; held() }
        }
        return captured
    }
    func saveConfiguration(_ computers: [RemoteDevice], basedOn revision: UUID) throws {
        snapshot = .init(revision: UUID(), computers: computers)
    }
    func synchronize(using transport: any ComputerSyncTransport) async throws {
        snapshot = .init(revision: UUID(), computers: [RemoteDevice(name: "Earlier sync", host: "sync.invalid")])
    }
    func release() { continuation?.resume(); continuation = nil }
}

private actor SyncLibrarySession: ComputerSyncLibrarySession {
    private var snapshot = ComputerSyncCoordinator.LibrarySnapshot(revision: UUID(), computers: [])
    private let fails: Bool
    private let held: (@Sendable () -> Void)?
    private var continuation: CheckedContinuation<Void, Never>?
    init(fails: Bool, held: (@Sendable () -> Void)? = nil) { self.fails = fails; self.held = held }
    func activate() async throws {}
    func librarySnapshot() -> ComputerSyncCoordinator.LibrarySnapshot { snapshot }
    func saveConfiguration(_ computers: [RemoteDevice], basedOn revision: UUID) throws {}
    func synchronize(using transport: any ComputerSyncTransport) async throws {
        if let held {
            await withCheckedContinuation { continuation in self.continuation = continuation; held() }
        }
        snapshot = .init(revision: UUID(), computers: [RemoteDevice(name: "Merged", host: "generated.invalid")])
        if fails { throw ComputerSyncCoordinator.Failure.retryLimit }
    }
    func release() { continuation?.resume(); continuation = nil }
}

private struct UnusedTransport: ComputerSyncTransport {
    func fetch() async throws -> CloudKitComputerSyncReader.Read { throw CancellationError() }
    func save(journal: Data, accountIdentifier: String, expectedChangeTag: String?) async throws -> CloudKitComputerSyncReader.Read {
        throw CancellationError()
    }
}

private actor HeldLibrarySession: ComputerSyncLibrarySession {
    private let snapshot: ComputerSyncCoordinator.LibrarySnapshot
    private let held: (@Sendable () -> Void)?
    private var continuation: CheckedContinuation<Void, Never>?
    init(name: String, held: (@Sendable () -> Void)? = nil) {
        snapshot = .init(revision: UUID(), computers: [RemoteDevice(name: name, host: "generated.invalid")])
        self.held = held
    }
    func activate() async throws {
        if let held {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                held()
            }
        }
    }
    func release() { continuation?.resume(); continuation = nil }
    func librarySnapshot() -> ComputerSyncCoordinator.LibrarySnapshot { snapshot }
    func saveConfiguration(_ computers: [RemoteDevice], basedOn revision: UUID) throws {
        throw ComputerSyncCoordinator.Failure.libraryChanged
    }
    func synchronize(using transport: any ComputerSyncTransport) async throws {}
}
