import Foundation

/// Durable offline replica storage. An external coordinator chooses when to publish or receive.
/// No account data or passwords are read; no production iCloud container is accessed here.
public final class DeviceSyncStore: @unchecked Sendable {
    public static let documentKey = "com.aethernative.aetherscreens.sync.devices.v1"
    private static let replicaKey = "com.aethernative.aetherscreens.sync.replica.v1"
    private static let persistenceLock = NSLock()
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var document: DeviceSyncDocument
    private var storedData: Data?

    public let replicaID: UUID

    public init(defaults: UserDefaults) throws {
        Self.persistenceLock.lock(); defer { Self.persistenceLock.unlock() }
        self.defaults = defaults
        let replicaID: UUID
        if let stored = defaults.string(forKey: Self.replicaKey) {
            guard let identifier = UUID(uuidString: stored) else {
                throw DeviceSyncDocument.Failure.invalidDocument
            }
            replicaID = identifier
        } else {
            replicaID = UUID()
            defaults.set(replicaID.uuidString, forKey: Self.replicaKey)
        }
        self.replicaID = replicaID
        if let data = defaults.data(forKey: Self.documentKey) {
            document = try DeviceSyncDocument(data: data, replicaID: replicaID)
            storedData = data
        } else {
            document = .init(replicaID: replicaID)
        }
    }

    /// The caller supplies its complete saved list, including local offline edits/deletions.
    @discardableResult
    public func recordLocalDevices(_ devices: [RemoteDevice]) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        var candidate = document
        guard try candidate.recordLocalDevices(devices) else { return false }
        try persist(candidate)
        return true
    }

    public func exportedData() throws -> Data {
        lock.lock(); defer { lock.unlock() }
        return try document.encoded()
    }

    @discardableResult
    public func recordLocalPreferences(language: AppLanguage?,
                                      keyboards: [UUID: KeyboardToolbarConfiguration]) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        var candidate = document
        guard try candidate.recordLocalPreferences(language: language, keyboards: keyboards) else { return false }
        try persist(candidate)
        return true
    }

    public var applicationLanguage: AppLanguage? {
        lock.lock(); defer { lock.unlock() }; return document.applicationLanguage
    }

    public var keyboardConfigurations: [UUID: KeyboardToolbarConfiguration] {
        lock.lock(); defer { lock.unlock() }; return document.keyboardConfigurations
    }

    /// Call only after recording local changes; invalid incoming bytes cannot overwrite local data.
    @discardableResult
    public func receive(_ data: Data) throws -> Bool {
        try receiveDocuments([data])
    }

    /// Import a fetched batch atomically: a malformed replica cannot leave a partial import.
    @discardableResult
    public func receiveDocuments(_ documents: [Data]) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        var candidate = document
        var changed = false
        for data in documents {
            let incoming = try DeviceSyncDocument(data: data, replicaID: document.replicaID)
            if try candidate.merge(incoming) { changed = true }
        }
        // Persist learned clocks even when all incoming values were already superseded.
        try persist(candidate)
        return changed
    }

    public func devices(retainingLocalState devices: [RemoteDevice] = []) -> [RemoteDevice] {
        lock.lock(); defer { lock.unlock() }
        return document.devices(retainingLocalState: devices)
    }

    private func persist(_ candidate: DeviceSyncDocument) throws {
        Self.persistenceLock.lock(); defer { Self.persistenceLock.unlock() }
        // A coordinator owns one replica. Refuse stale extra instances rather than overwriting
        // metadata saved by another instance in this process; callers must reopen and reconcile.
        guard defaults.data(forKey: Self.documentKey) == storedData else {
            throw DeviceSyncDocument.Failure.staleLocalReplica
        }
        let data = try candidate.encoded()
        defaults.set(data, forKey: Self.documentKey)
        storedData = data
        document = candidate
    }
}
