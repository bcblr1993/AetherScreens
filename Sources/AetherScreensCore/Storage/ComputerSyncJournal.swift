import Foundation

/// Explicit whitelist: runtime status, thumbnails and credential bytes are not sync metadata.
public struct ComputerSyncMetadata: Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var host: String
    public var port: UInt16
    public var deviceType: RemoteDevice.DeviceType
    public var authMethod: RemoteDevice.AuthMethod
    public var username: String?
    public var isTailscaleNode: Bool
    public var macAddress: String?
    /// Opaque key identifiers may be shared; missing local keys remain fail-closed.
    public var ssh: SSHConnectionSettings?

    public init(device: RemoteDevice) {
        id = device.id; name = device.name; host = device.host; port = device.port
        deviceType = device.deviceType; authMethod = device.authMethod; username = device.username
        isTailscaleNode = device.isTailscaleNode; macAddress = device.macAddress; ssh = device.ssh
    }

    fileprivate var isValid: Bool {
        name.utf8.count <= 4096 && host.utf8.count <= 1024
            && (username?.utf8.count ?? 0) <= 1024 && (macAddress?.utf8.count ?? 0) <= 128
            && ConnectionRequest(host: host, port: String(port)) != nil
    }
}

/// Logical versions avoid clock skew; deletion records are retained for offline peers.
public struct ComputerSyncJournal: Sendable {
    public enum Failure: Error, Equatable {
        case unsupportedSchema, invalidRecord, conflictingVersion, capacityExceeded, clockExhausted, deletedRecord
    }
    public struct Version: Codable, Equatable, Comparable, Sendable {
        public let counter: UInt64
        public let peer: UUID
        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.counter == rhs.counter ? lhs.peer.uuidString < rhs.peer.uuidString : lhs.counter < rhs.counter
        }
    }
    public struct Record: Codable, Equatable, Sendable {
        public let id: UUID
        public let version: Version
        /// Nil is a tombstone, not an absent record.
        public let metadata: ComputerSyncMetadata?
    }
    public struct MergeResult: Equatable, Sendable {
        public let didChangeRecords: Bool
        public let didAdvanceClock: Bool
        public let remoteNeedsUpdate: Bool
    }
    private struct Document: Codable {
        let schema: Int
        let peer: UUID
        let counter: UInt64
        let records: [Record]
    }
    public static let maximumBytes = 512 * 1024
    public static let maximumRecords = 1000
    public let peer: UUID
    public private(set) var counter: UInt64 = 0
    public private(set) var records: [UUID: Record] = [:]

    public init(peer: UUID = UUID()) { self.peer = peer }

    /// Restore the local peer identity and logical clock together after relaunch.
    public init(restoring data: Data) throws {
        let document = try Self.decode(data)
        self.peer = document.peer
        self.counter = document.counter
        self.records = Dictionary(uniqueKeysWithValues: document.records.map { ($0.id, $0) })
    }

    public var computers: [ComputerSyncMetadata] {
        records.values.compactMap(\.metadata).sorted { $0.id.uuidString < $1.id.uuidString }
    }

    public mutating func upsert(_ metadata: ComputerSyncMetadata) throws {
        guard metadata.isValid else { throw Failure.invalidRecord }
        if let existing = records[metadata.id], existing.metadata == nil { throw Failure.deletedRecord }
        if records[metadata.id]?.metadata == metadata { return }
        try write(id: metadata.id, metadata: metadata)
    }

    public mutating func delete(_ id: UUID) throws {
        if let record = records[id], record.metadata == nil { return }
        try write(id: id, metadata: nil)
    }

    /// Capture a complete saved-computer list, never a filtered/search result.
    /// Only changed configuration advances the clock; missing known IDs become tombstones.
    @discardableResult
    public mutating func captureLocalComputers(_ devices: [RemoteDevice]) throws -> Bool {
        let metadata = devices.map(ComputerSyncMetadata.init(device:))
        let ids = Set(metadata.map(\.id))
        guard ids.count == metadata.count, metadata.allSatisfy(\.isValid) else { throw Failure.invalidRecord }
        var candidate = self
        var changes: [(UUID, ComputerSyncMetadata?)] = []
        for value in metadata {
            if let existing = records[value.id], existing.metadata == nil { throw Failure.deletedRecord }
            if records[value.id]?.metadata != value { changes.append((value.id, value)) }
        }
        for record in records.values where record.metadata != nil && !ids.contains(record.id) {
            changes.append((record.id, nil))
        }
        guard !changes.isEmpty else { return false }
        for (id, value) in changes.sorted(by: { $0.0.uuidString < $1.0.uuidString }) {
            guard candidate.counter < UInt64.max else { throw Failure.clockExhausted }
            candidate.counter += 1
            candidate.records[id] = Record(id: id,
                version: Version(counter: candidate.counter, peer: peer), metadata: value)
        }
        guard candidate.records.count <= Self.maximumRecords else { throw Failure.capacityExceeded }
        _ = try candidate.encoded() // One full encoding for a batch, before publication.
        self = candidate
        return true
    }

    private mutating func write(id: UUID, metadata: ComputerSyncMetadata?) throws {
        guard counter < UInt64.max else { throw Failure.clockExhausted }
        guard records[id] != nil || records.count < Self.maximumRecords else { throw Failure.capacityExceeded }
        var candidate = self
        candidate.counter += 1
        candidate.records[id] = Record(id: id, version: Version(counter: candidate.counter, peer: peer), metadata: metadata)
        _ = try candidate.encoded() // Check the complete document before committing.
        self = candidate
    }

    /// Validate and merge atomically; a corrupt record never partially applies a snapshot.
    @discardableResult
    public mutating func merge(_ data: Data) throws -> MergeResult {
        let incoming = try Self.decode(data)
        var candidate = self
        for remote in incoming.records {
            if let local = candidate.records[remote.id] {
                if local.version == remote.version && local != remote { throw Failure.conflictingVersion }
                // Deletion wins even over an unaware offline peer's later edit.
                // Re-adding a computer uses a new identity, never clears a tombstone.
                if local.metadata == nil && remote.metadata != nil { continue }
                if (local.metadata == nil) == (remote.metadata == nil), local.version >= remote.version { continue }
            }
            candidate.records[remote.id] = remote
        }
        candidate.counter = max(candidate.counter, incoming.counter)
        guard candidate.records.count <= Self.maximumRecords else { throw Failure.capacityExceeded }
        _ = try candidate.encoded()
        let result = MergeResult(didChangeRecords: candidate.records != records,
            didAdvanceClock: candidate.counter != counter,
            remoteNeedsUpdate: candidate.records != Dictionary(uniqueKeysWithValues: incoming.records.map { ($0.id, $0) }))
        self = candidate
        return result
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Document(schema: 1, peer: peer, counter: counter,
            records: records.values.sorted { $0.id.uuidString < $1.id.uuidString }))
        guard data.count <= Self.maximumBytes else { throw Failure.capacityExceeded }
        return data
    }

    private static func decode(_ data: Data) throws -> Document {
        guard data.count <= maximumBytes else { throw Failure.capacityExceeded }
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.schema == 1 else { throw Failure.unsupportedSchema }
        guard document.records.count <= maximumRecords else { throw Failure.capacityExceeded }
        var ids = Set<UUID>()
        for record in document.records {
            guard ids.insert(record.id).inserted, record.version.counter > 0,
                  record.version.counter <= document.counter,
                  record.metadata == nil || (record.metadata?.id == record.id && record.metadata?.isValid == true)
            else { throw Failure.invalidRecord }
        }
        return document
    }
}
