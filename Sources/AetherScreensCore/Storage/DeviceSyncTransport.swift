import Foundation

public enum DeviceSyncFailure: Error, Equatable, Sendable {
    case accountUnavailable, accountChanged, remoteConflict, invalidRemoteData, busy, tooManyReplicas
    case localStorageSelected, configurationChanged
}

/// A replica may own an offline document or the actual saved-computer library.
/// Library implementations commit the materialized list together with its document.
public protocol DeviceSyncReplica: Sendable {
    var replicaID: UUID { get }
    func recordLocalDevices(_ devices: [RemoteDevice]) throws -> Bool
    func prepareForExchange() throws
    func receiveDocuments(_ documents: [Data]) throws -> Bool
    func exportedData() throws -> Data
}

extension DeviceSyncStore: DeviceSyncReplica {
    public func prepareForExchange() throws {}
}

public struct DeviceSyncRemoteSnapshot: Sendable {
    public let documents: [Data]
    /// Opaque server version for this replica, never a version belonging to another replica.
    public let localReplicaVersion: Data?

    public init(documents: [Data], localReplicaVersion: Data? = nil) {
        self.documents = documents; self.localReplicaVersion = localReplicaVersion
    }
}

/// Implementations must bind every operation to the supplied account and conditionally publish
/// only the caller's replica. A stale version must fail instead of overwriting unseen changes.
public protocol DeviceSyncTransport: Sendable {
    func accountIdentifier() async throws -> String
    func fetchDocuments(replicaID: UUID, account: String) async throws -> DeviceSyncRemoteSnapshot
    func publish(_ document: Data, replicaID: UUID, account: String, version: Data?) async throws
}

/// One exchange at a time; the local store can still receive foreground edits during network waits.
/// This coordinator has no automatic production transport or access to a user's account.
public actor DeviceSyncExchange {
    public enum Outcome: Equatable, Sendable { case synchronized, pendingLocalChanges }
    private let store: any DeviceSyncReplica
    private let transport: any DeviceSyncTransport
    private let defaults: UserDefaults
    private let accountKey: String
    private let afterVerifiedExchange: (@Sendable (String) async throws -> Void)?
    private var exchanging = false

    public init(store: any DeviceSyncReplica, transport: any DeviceSyncTransport, defaults: UserDefaults,
                accountKey: String = "com.aethernative.aetherscreens.sync.bound-account.v1",
                afterVerifiedExchange: (@Sendable (String) async throws -> Void)? = nil) {
        self.store = store; self.transport = transport; self.defaults = defaults
        self.accountKey = accountKey
        self.afterVerifiedExchange = afterVerifiedExchange
    }

    /// A local/cloud settings controller calls this only after the user selects iCloud.
    /// Account switching requires a separate reviewed migration; never silently rebind local data.
    public func synchronize(localDevices: [RemoteDevice]? = nil) async throws -> Outcome {
        guard !exchanging else { throw DeviceSyncFailure.busy }
        exchanging = true; defer { exchanging = false }
        try Task.checkCancellation()
        if let localDevices { _ = try store.recordLocalDevices(localDevices) }
        try store.prepareForExchange()
        let account = try await transport.accountIdentifier()
        try Task.checkCancellation()
        guard !account.isEmpty else { throw DeviceSyncFailure.accountUnavailable }
        if let bound = defaults.string(forKey: accountKey) {
            guard bound == account else { throw DeviceSyncFailure.accountChanged }
        } else {
            defaults.set(account, forKey: accountKey)
        }
        try store.prepareForExchange()
        let snapshot = try await transport.fetchDocuments(replicaID: store.replicaID, account: account)
        try Task.checkCancellation()
        guard snapshot.documents.count <= 32 else { throw DeviceSyncFailure.tooManyReplicas }
        guard try await transport.accountIdentifier() == account else { throw DeviceSyncFailure.accountChanged }
        try Task.checkCancellation()
        _ = try store.receiveDocuments(snapshot.documents)
        let outgoing = try store.exportedData()
        try await transport.publish(outgoing, replicaID: store.replicaID,
                                    account: account, version: snapshot.localReplicaVersion)
        try Task.checkCancellation()
        guard try await transport.accountIdentifier() == account else { throw DeviceSyncFailure.accountChanged }
        try Task.checkCancellation()
        try await afterVerifiedExchange?(account)
        try Task.checkCancellation()
        return try store.exportedData() == outgoing ? .synchronized : .pendingLocalChanges
    }
}
