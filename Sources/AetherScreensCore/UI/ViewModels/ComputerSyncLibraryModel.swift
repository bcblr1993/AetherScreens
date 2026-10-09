import Foundation
import Combine

protocol ComputerSyncLibrarySession: Sendable {
    func activate() async throws
    func librarySnapshot() async throws -> ComputerSyncCoordinator.LibrarySnapshot
    func saveConfiguration(_ computers: [RemoteDevice], basedOn revision: UUID) async throws
    func synchronize(using transport: any ComputerSyncTransport) async throws
}

extension ComputerSyncCoordinator: ComputerSyncLibrarySession {}

/// UI boundary for the future account selector/editor. No shared Store mutation,
/// provider connection or automatic cloud activation occurs here.
@MainActor
final class ComputerSyncLibraryModel: ObservableObject {
    enum Failure: Equatable { case recoveryRequired, libraryChanged, saveFailed, syncFailed }
    @Published private(set) var snapshot: ComputerSyncCoordinator.LibrarySnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var isSynchronizing = false
    @Published private(set) var failure: Failure?
    private var session: (any ComputerSyncLibrarySession)?
    private var generation = UUID()
    private var refreshGeneration = UUID()

    func select(_ selected: any ComputerSyncLibrarySession) async {
        let token = UUID()
        generation = token
        session = selected
        snapshot = nil
        failure = nil
        isLoading = true
        isSaving = false
        isSynchronizing = false
        defer { if generation == token { isLoading = false } }
        do {
            try await selected.activate()
            let loaded = try await selected.librarySnapshot()
            guard generation == token else { return }
            snapshot = loaded
        } catch {
            guard generation == token else { return }
            failure = .recoveryRequired
        }
    }

    func deselect() {
        generation = UUID()
        session = nil
        snapshot = nil
        failure = nil
        isLoading = false
        isSaving = false
        isSynchronizing = false
    }

    /// A failed upload can still have durably merged a remote update. Refresh
    /// the account's snapshot in both cases without publishing old generations.
    func synchronize(using transport: any ComputerSyncTransport) async -> Bool {
        guard let session, snapshot != nil, !isLoading, !isSynchronizing else { return false }
        let token = generation
        isSynchronizing = true
        failure = nil
        defer { if generation == token { isSynchronizing = false } }
        do {
            try await session.synchronize(using: transport)
            try await refresh(session, accountGeneration: token)
            guard generation == token else { return false }
            return true
        } catch {
            try? await refresh(session, accountGeneration: token)
            guard generation == token else { return false }
            failure = .syncFailed
            return false
        }
    }

    /// The caller retains its form draft. Failure does not replace that draft or
    /// turn an old-account completion into success for the newly selected account.
    func save(_ computers: [RemoteDevice], basedOn revision: UUID) async -> Bool {
        guard let session, snapshot != nil, !isLoading, !isSaving else { return false }
        let token = generation
        isSaving = true
        failure = nil
        defer { if generation == token { isSaving = false } }
        do {
            try await session.saveConfiguration(computers, basedOn: revision)
            try await refresh(session, accountGeneration: token)
            guard generation == token else { return false }
            return true
        } catch {
            guard generation == token else { return false }
            if case ComputerSyncCoordinator.Failure.libraryChanged = error { failure = .libraryChanged }
            else { failure = .saveFailed }
            return false
        }
    }

    /// Saving and syncing may overlap within one account. An older suspended
    /// snapshot read must not replace a newer read published by the other task.
    private func refresh(_ session: any ComputerSyncLibrarySession, accountGeneration token: UUID) async throws {
        guard generation == token else { return }
        let request = UUID()
        refreshGeneration = request
        let updated = try await session.librarySnapshot()
        guard generation == token, refreshGeneration == request else { return }
        snapshot = updated
    }
}
