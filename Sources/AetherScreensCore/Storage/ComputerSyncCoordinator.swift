import Foundation
import CloudKit

/// Serial local lifecycle for one provider account. The caller must supply an
/// account-specific Store and route every configuration mutation through here.
/// No provider login, transport, or secret synchronization is enabled by this type.
actor ComputerSyncCoordinator {
    enum Failure: Error { case notActivated, libraryChanged, synchronizationInProgress, retryLimit }
    struct LibrarySnapshot: Sendable {
        let revision: UUID
        let computers: [RemoteDevice]
    }
    private let store: DeviceStore
    private let scope: ComputerSyncAccountScope
    private let checkpointURL: URL
    private let accountIdentifier: String
    private var synchronizing = false
    private var activated = false
    private var revision = UUID()

    init(store: DeviceStore, accountIdentifier: String, rootDirectory: URL) throws {
        self.store = store
        self.accountIdentifier = accountIdentifier
        scope = try ComputerSyncAccountScope(accountIdentifier: accountIdentifier)
        checkpointURL = rootDirectory.appendingPathComponent(scope.digest, isDirectory: true)
            .appendingPathComponent("checkpoint.json")
    }

    /// Recovery precedes editing; a corrupt or mismatched commit never falls back
    /// to a fresh peer identity or silently adopts the preference mirror.
    func activate() throws {
        activated = false
        try FileManager.default.createDirectory(at: checkpointURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        if try !store.recoverSyncCheckpoint(at: checkpointURL, accountScope: scope) {
            _ = try store.captureLocalSyncJournal(checkpointURL: checkpointURL, accountScope: scope)
        }
        activated = true
        revision = UUID()
    }

    func computers() throws -> [RemoteDevice] {
        guard activated else { throw Failure.notActivated }
        return store.devices
    }

    /// Preserve each remote merge durably before uploading; server conflicts
    /// re-fetch and merge, never retry an unconditional overwrite. Local edits
    /// made while the upload awaits are captured on the next bounded attempt.
    func synchronize(using transport: any ComputerSyncTransport) async throws {
        guard activated else { throw Failure.notActivated }
        guard !synchronizing else { throw Failure.synchronizationInProgress }
        synchronizing = true
        defer { synchronizing = false }
        for _ in 0..<3 {
            try Task.checkCancellation()
            let remote = try await transport.fetch()
            try Task.checkCancellation()
            guard remote.accountIdentifier == accountIdentifier else {
                throw CloudKitComputerSyncReader.Failure.accountChanged
            }
            if let snapshot = remote.snapshot {
                let merged = try mergeRemoteSnapshot(snapshot.journal)
                if !merged.remoteNeedsUpdate { return }
            }
            let outgoing = try exportSnapshot()
            do {
                let saved = try await transport.save(journal: outgoing, accountIdentifier: accountIdentifier,
                                                     expectedChangeTag: remote.snapshot?.changeTag)
                try Task.checkCancellation()
                guard saved.accountIdentifier == accountIdentifier else {
                    throw CloudKitComputerSyncReader.Failure.accountChanged
                }
                guard let snapshot = saved.snapshot, snapshot.journal == outgoing, !snapshot.changeTag.isEmpty else {
                    throw CloudKitComputerSyncReader.Failure.invalidRecord
                }
                if try exportSnapshot() == outgoing { return }
            } catch CloudKitComputerSyncReader.Failure.versionConflict { continue }
            catch let error as CKError where error.code == .serverRecordChanged { continue }
        }
        throw Failure.retryLimit
    }

    func librarySnapshot() throws -> LibrarySnapshot {
        guard activated else { throw Failure.notActivated }
        return LibrarySnapshot(revision: revision, computers: store.devices)
    }

    func saveConfiguration(_ fullLibrary: [RemoteDevice], basedOn expectedRevision: UUID) throws {
        guard activated else { throw Failure.notActivated }
        guard expectedRevision == revision else { throw Failure.libraryChanged }
        let changed = fullLibrary != store.devices
        do {
            try store.commitLocalSyncConfiguration(fullLibrary, checkpointURL: checkpointURL, accountScope: scope)
            if changed { revision = UUID() }
        }
        catch { activated = false; throw error }
    }

    func mergeRemoteSnapshot(_ data: Data) throws -> ComputerSyncJournal.MergeResult {
        guard activated else { throw Failure.notActivated }
        do {
            let before = store.devices
            let result = try store.mergeSyncSnapshot(data, checkpointURL: checkpointURL, accountScope: scope)
            if before != store.devices { revision = UUID() }
            return result
        }
        catch { activated = false; throw error }
    }

    /// Only the metadata journal leaves the local boundary, never the checkpoint.
    func exportSnapshot() throws -> Data {
        guard activated else { throw Failure.notActivated }
        do { return try store.captureLocalSyncJournal(checkpointURL: checkpointURL, accountScope: scope).encoded() }
        catch { activated = false; throw error }
    }
}
