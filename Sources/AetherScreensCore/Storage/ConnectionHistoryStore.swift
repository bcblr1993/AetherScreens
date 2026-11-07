import Foundation

/// A single recorded remote desktop connection attempt and its session duration/outcome.
public struct ConnectionHistoryEntry: Codable, Identifiable, Equatable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        case active = "Active"
        case completed = "Completed"
        case failed = "Failed"
    }

    public let id: UUID
    public let deviceID: UUID
    public var deviceName: String
    public var host: String
    public var port: UInt16
    public var remoteProtocol: RemoteDevice.RemoteProtocol
    public let startedAt: Date
    public var endedAt: Date?
    public var outcome: Outcome

    public var durationSeconds: Int? {
        guard let endedAt else { return nil }
        return max(0, Int(endedAt.timeIntervalSince(startedAt).rounded()))
    }

    public init(
        id: UUID = UUID(),
        deviceID: UUID,
        deviceName: String,
        host: String,
        port: UInt16,
        remoteProtocol: RemoteDevice.RemoteProtocol,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        outcome: Outcome = .active
    ) {
        self.id = id
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.host = host
        self.port = port
        self.remoteProtocol = remoteProtocol
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.outcome = outcome
    }
}

/// Bounded ring-buffer store tracking recent connection history across devices without unbounded memory or preference growth.
@MainActor
public final class ConnectionHistoryStore: ObservableObject {
    public static let shared = ConnectionHistoryStore()
    public static let storageKey = "com.aethernative.aetherscreens.connectionHistory"

    @Published public private(set) var entries: [ConnectionHistoryEntry] = []
    private let defaults: UserDefaults
    private let maxEntries: Int

    public init(defaults: UserDefaults = .standard, maxEntries: Int = 100) {
        self.defaults = defaults
        self.maxEntries = max(1, maxEntries)
        load()
    }

    public func load() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([ConnectionHistoryEntry].self, from: data) else {
            entries = []
            return
        }
        entries = Array(decoded.prefix(maxEntries))
    }

    @discardableResult
    public func recordSessionStart(
        deviceID: UUID,
        deviceName: String,
        host: String,
        port: UInt16,
        remoteProtocol: RemoteDevice.RemoteProtocol,
        startedAt: Date = Date()
    ) -> UUID {
        let entry = ConnectionHistoryEntry(
            deviceID: deviceID,
            deviceName: deviceName,
            host: host,
            port: port,
            remoteProtocol: remoteProtocol,
            startedAt: startedAt,
            outcome: .active
        )
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        persist()
        return entry.id
    }

    public func recordSessionEnd(
        id: UUID,
        endedAt: Date = Date(),
        outcome: ConnectionHistoryEntry.Outcome = .completed
    ) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].endedAt = endedAt
        entries[idx].outcome = outcome
        persist()
    }

    public func entries(for deviceID: UUID) -> [ConnectionHistoryEntry] {
        entries.filter { $0.deviceID == deviceID }
    }

    public func clearAll() {
        entries.removeAll()
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func persist() {
        if let encoded = try? JSONEncoder().encode(entries) {
            defaults.set(encoded, forKey: Self.storageKey)
        }
    }
}
