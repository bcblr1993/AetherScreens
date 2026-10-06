import Foundation
import Combine
import CloudKit

public enum DeviceLibrarySyncIssue: Error, Equatable, Sendable {
    case notConfigured, accountUnavailable, accountChanged, network, conflict, invalidData, quota, localStorage, credentials, credentialTarget

    public var messageKey: String {
        switch self {
        case .notConfigured: return "iCloud synchronization is unavailable in this build."
        case .accountUnavailable: return "Sign in to iCloud in system settings, then retry."
        case .accountChanged: return "The iCloud account has changed. Your saved computers remain on this device."
        case .network: return "Could not sync. Your changes are saved on this device. Retry when connected."
        case .conflict: return "Other changes arrived during sync. Retry to merge them."
        case .invalidData: return "Could not read synchronization data. Your local computers are preserved."
        case .quota: return "The synchronization storage limit was reached. Your changes remain on this device."
        case .localStorage: return "Could not save the storage setting. Your current storage choice is preserved."
        case .credentials: return "Computers synchronized, but credentials could not sync. Retry when Keychain is available."
        case .credentialTarget: return "Re-enter credentials for the edited computer before syncing again."
        }
    }

    static func classify(_ error: Error) -> Self {
        if let issue = error as? Self { return issue }
        if let failure = error as? DeviceCredentialSyncStore.Failure {
            switch failure {
            case .notConfigured: return .notConfigured
            case .conflict: return .conflict
            case .credentialMismatch: return .credentialTarget
            default: return .credentials
            }
        }
        if let failure = error as? DeviceSyncFailure {
            switch failure {
            case .accountUnavailable: return .accountUnavailable
            case .accountChanged: return .accountChanged
            case .remoteConflict: return .conflict
            case .tooManyReplicas: return .quota
            case .invalidRemoteData: return .invalidData
            default: return .localStorage
            }
        }
        if let failure = error as? DeviceSyncDocument.Failure {
            switch failure {
            case .quotaExceeded: return .quota
            default: return .invalidData
            }
        }
        if let error = error as? CKError {
            switch error.code {
            case .notAuthenticated, .accountTemporarilyUnavailable: return .accountUnavailable
            case .quotaExceeded: return .quota
            case .serverRecordChanged: return .conflict
            case .missingEntitlement, .badContainer, .permissionFailure: return .notConfigured
            default: return .network
            }
        }
        return .network
    }
}

public enum DeviceLibrarySyncStatus: Equatable, Sendable {
    case local, pending, synchronizing, synchronized, failed(DeviceLibrarySyncIssue)

    public var messageKey: String {
        switch self {
        case .local: return "Saved computers stay on this device."
        case .pending: return "Changes are waiting to sync."
        case .synchronizing: return "Syncing saved computers…"
        case .synchronized: return "Saved computers synchronized."
        case .failed(let issue): return issue.messageKey
        }
    }
}

/// Owns app-level scheduling. A transport is supplied only after its signed CloudKit
/// container is provisioned; an unconfigured build never constructs CKContainer.
@MainActor
public final class DeviceLibrarySyncController: ObservableObject {
    public typealias TransportFactory = @Sendable () throws -> any DeviceSyncTransport
    public typealias CredentialFactory = @Sendable (String) throws -> DeviceCredentialSyncStore
    @Published public private(set) var storageMode: DeviceLibraryStorage
    @Published public private(set) var status: DeviceLibrarySyncStatus

    private let store: DeviceStore
    private let transportFactory: TransportFactory?
    private let credentialFactory: CredentialFactory?
    private let debounceNanoseconds: UInt64
    private var observers = Set<AnyCancellable>()
    private var exchange: DeviceSyncExchange?
    private var operation: Task<Void, Never>?
    private var scheduled: Task<Void, Never>?
    private var generation = UUID()
    private var automatic = false
    private var anotherPass = false

    public init(store: DeviceStore, transportFactory: TransportFactory? = nil,
                credentialFactory: CredentialFactory? = nil,
                debounceNanoseconds: UInt64 = 500_000_000) {
        self.store = store; self.transportFactory = transportFactory
        self.credentialFactory = credentialFactory
        self.debounceNanoseconds = debounceNanoseconds
        let initialMode = store.storageMode
        storageMode = initialMode
        status = initialMode == .local ? .local : .pending
        // Recover the encrypted LOCAL queue for the previously bound metadata
        // owner before accepting offline edits. This never enables cloud access
        // or silently rebinds the owner after an account change.
        if let credentialFactory,
           let bound = store.synchronizationDefaults.string(forKey: "com.aethernative.aetherscreens.sync.bound-account.v1") {
            do { store.installLocalCredentialProvider(try credentialFactory(bound)) }
            catch { status = .failed(.classify(error)) }
        }
        NotificationCenter.default.publisher(for: DeviceStore.libraryDidChange)
            .filter { ($0.object as? DeviceStore) === store }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self else { return }
                self.libraryChanged(notification)
            }.store(in: &observers)
        NotificationCenter.default.publisher(for: .CKAccountChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.accountChanged() }
            .store(in: &observers)
    }

    deinit { operation?.cancel(); scheduled?.cancel() }

    public func selectStorage(_ choice: DeviceLibraryStorage) {
        guard choice != storageMode else { return }
        do { try store.selectStorage(choice) }
        catch { status = .failed(.classify(error)); return }
        invalidateExchange()
        storageMode = store.storageMode
        status = storageMode == .local ? .local : .pending
        if storageMode == .iCloud { schedule() }
    }

    public func resumeAutomaticSynchronization() {
        automatic = true
        if storageMode == .iCloud { schedule() }
    }

    public func suspendAutomaticSynchronization() {
        automatic = false
        invalidateExchange()
        if storageMode == .iCloud, status == .synchronizing { status = .pending }
    }

    public func synchronizeNow() async {
        scheduled?.cancel(); scheduled = nil
        guard storageMode == .iCloud else { status = .local; return }
        if let operation { await operation.value; return }
        let current = generation
        let owned = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.performExchange(generation: current)
        }
        operation = owned
        await owned.value
        guard current == generation else { return }
        operation = nil
        if anotherPass, status == .synchronized || status == .pending {
            anotherPass = false
            status = .pending
            schedule()
        }
    }

    private func performExchange(generation current: UUID) async {
        guard current == generation else { return }
        status = .synchronizing
        do {
            guard let transportFactory else { throw DeviceLibrarySyncIssue.notConfigured }
            store.suspendCredentialSynchronization()
            if exchange == nil {
                exchange = try DeviceSyncExchange(store: store.synchronizationReplica(),
                                                  transport: transportFactory(),
                                                  defaults: store.synchronizationDefaults,
                                                  afterVerifiedExchange: { [weak self] account in
                    guard let self else { throw CancellationError() }
                    try await self.synchronizeCredentials(account: account, generation: current)
                })
            }
            guard let exchange else { return }
            let outcome = try await exchange.synchronize()
            guard current == generation, !Task.isCancelled else { return }
            status = outcome == .synchronized ? .synchronized : .pending
            if outcome == .pendingLocalChanges { anotherPass = true }
        } catch {
            guard current == generation, !Task.isCancelled else { return }
            status = .failed(.classify(error))
        }
    }

    private func synchronizeCredentials(account: String, generation current: UUID) throws {
        guard current == generation, !Task.isCancelled, storageMode == .iCloud else {
            throw DeviceSyncFailure.configurationChanged
        }
        if let credentialFactory { try store.synchronizeCredentials(using: credentialFactory(account)) }
    }

    private func schedule() {
        guard automatic, storageMode == .iCloud else { return }
        if operation != nil { anotherPass = true; return }
        scheduled?.cancel()
        let delay = debounceNanoseconds
        scheduled = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.scheduled = nil
            await self.synchronizeNow()
        }
    }

    private func libraryChanged(_ notification: Notification) {
        if storageMode != store.storageMode {
            invalidateExchange()
            storageMode = store.storageMode
            status = storageMode == .local ? .local : .pending
        }
        guard storageMode == .iCloud,
              notification.userInfo?["origin"] as? DeviceLibraryChangeOrigin == .local,
              (notification.userInfo?["metadataChanged"] as? Bool == true ||
               notification.userInfo?["credentialsChanged"] as? Bool == true) else { return }
        if let failure = store.credentialSynchronizationFailure {
            status = .failed(.classify(failure))
            return
        }
        if status != .synchronizing { status = .pending }
        schedule()
    }

    private func accountChanged() {
        guard storageMode == .iCloud else { return }
        invalidateExchange()
        status = .pending
        schedule()
    }

    private func invalidateExchange() {
        store.suspendCredentialSynchronization()
        generation = UUID()
        operation?.cancel(); operation = nil
        scheduled?.cancel(); scheduled = nil
        exchange = nil; anotherPass = false
    }
}
