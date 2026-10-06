import Foundation
import Combine

/// A process-local inbox; native intents submit only an opaque saved identifier.
@MainActor
public final class ShortcutLaunchQueue: ObservableObject {
    public struct Request: Equatable, Sendable {
        public let token: UUID
        public let deviceID: UUID
        public let createdAt: TimeInterval
    }

    public enum Failure: Error, LocalizedError, Sendable {
        case notEnabled, full, unavailable

        public var errorDescription: String? {
            switch self {
            case .notEnabled: return "This computer is not enabled for Shortcuts."
            case .full: return "The shortcut queue is full. Open the app and try again."
            case .unavailable: return "The shortcut request is unavailable. Open the app and try again."
            }
        }
    }

    public static let shared = ShortcutLaunchQueue()
    public static let widgets = ShortcutLaunchQueue()
    @Published public private(set) var revision = 0
    private var pending: [Request] = []
    private let now: () -> TimeInterval
    private let capacity: Int
    private let lifetime: TimeInterval

    public init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                capacity: Int = 8, lifetime: TimeInterval = 30) {
        self.now = now
        self.capacity = min(max(capacity, 0), ShortcutCatalog.maximumEntries)
        self.lifetime = lifetime.isFinite && lifetime > 0 ? lifetime : 0
    }

    @discardableResult
    public func enqueue(deviceID: UUID, catalog: ShortcutCatalog) throws -> UUID {
        let time = now()
        expire(at: time)
        guard lifetime > 0, time.isFinite, time >= 0 else { throw Failure.unavailable }
        guard let enabled = catalog.validatedIDs, enabled.contains(deviceID) else { throw Failure.notEnabled }
        if let request = pending.first(where: { $0.deviceID == deviceID }) { return request.token }
        guard pending.count < capacity else { throw Failure.full }
        let request = Request(token: UUID(), deviceID: deviceID, createdAt: time)
        pending.append(request)
        changed()
        return request.token
    }

    /// A single MainActor call owns the claim and current opt-in/record checks.
    public func takeNext(isActive: Bool, isReady: Bool, catalog: ShortcutCatalog,
                         availableIDs: Set<UUID>) -> Request? {
        let time = now()
        expire(at: time)
        guard isActive, isReady, lifetime > 0, time.isFinite, time >= 0 else { return nil }
        let enabled = catalog.validatedIDs ?? []
        while !pending.isEmpty {
            let request = pending.removeFirst()
            changed()
            guard enabled.contains(request.deviceID), availableIDs.contains(request.deviceID) else { continue }
            return request
        }
        return nil
    }

    public func cancel(deviceID: UUID) {
        let count = pending.count
        pending.removeAll { $0.deviceID == deviceID }
        if pending.count != count { changed() }
    }

    private func expire(at time: TimeInterval) {
        let count = pending.count
        pending.removeAll { request in
            !time.isFinite || time < request.createdAt || lifetime <= 0 || time - request.createdAt >= lifetime
        }
        if pending.count != count { changed() }
    }

    private func changed() { revision &+= 1 }
}
