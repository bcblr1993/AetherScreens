import Foundation
import AetherScreensWidgetSupport

@MainActor
protocol SessionActivityDriver {
    var canStart: Bool { get }
    func existingActivities() -> [SessionActivityReference]
    func start(sessionID: UUID, state: SessionActivityContentState, staleDate: Date) throws -> String?
    func update(id: String, state: SessionActivityContentState, staleDate: Date) async
    func end(id: String, state: SessionActivityContentState, dismissAt: Date?) async
    func beginTerminalTask() -> (any SessionActivityCleanupLease)?
}

@MainActor
protocol SessionActivityCleanupLease {
    func end()
}

extension SessionActivityDriver {
    func beginTerminalTask() -> (any SessionActivityCleanupLease)? { nil }
}

struct SessionActivityReference {
    let id: String
    let sessionID: UUID
}

/// Display ownership is independent of network ownership. Callers must stop
/// their RFB/SSH session on real backgrounding; an Activity cannot keep it alive.
@MainActor
public final class SessionLiveActivityController {
    public enum EndReason: Sendable {
        case ended
        case failed
        case backgrounded

        var phase: SessionActivityPhase {
            switch self {
            case .ended: return .ended
            case .failed: return .failed
            case .backgrounded: return .paused
            }
        }
    }

    public static let shared = SessionLiveActivityController()
    private struct Record {
        let token: UUID
        var activityID: String?
    }
    private struct Operation {
        let token: UUID
        let task: Task<Void, Never>
    }

    private let driver: any SessionActivityDriver
    private let now: () -> Date
    private var records: [UUID: Record] = [:]
    private var suppressedSessions: Set<UUID> = []
    private var operations: [String: Operation] = [:]
    private var terminatingActivityIDs: Set<String> = []
    private var isForeground = true
    private var heartbeat: Task<Void, Never>?
    private let heartbeatInterval: UInt64?
    private let staleInterval: TimeInterval = 90
    private let finalDisplayInterval: TimeInterval = 60

    public convenience init() {
        self.init(driver: SystemSessionActivityDriver(), now: Date.init,
                  heartbeatInterval: 30_000_000_000)
    }

    init(driver: any SessionActivityDriver, now: @escaping () -> Date,
         heartbeatInterval: UInt64? = nil) {
        self.driver = driver
        self.now = now
        self.heartbeatInterval = heartbeatInterval
    }

    deinit { heartbeat?.cancel() }

    /// Call only after a successful connection, with a stable in-memory session ID.
    /// Permission denial or a system error must never affect the remote session.
    public func sessionConnected(sessionID: UUID) {
        guard isForeground, driver.canStart, records[sessionID] == nil,
              !suppressedSessions.contains(sessionID) else { return }
        let token = UUID()
        records[sessionID] = Record(token: token, activityID: nil)
        let date = now()
        do {
            let id = try driver.start(sessionID: sessionID,
                                      state: .init(phase: .connected, updatedAt: date),
                                      staleDate: date.addingTimeInterval(staleInterval))
            // An injected/system callback may synchronously retire this session.
            guard records[sessionID]?.token == token else {
                if let id {
                    endActivities([id], reason: isForeground ? .ended : .backgrounded)
                }
                return
            }
            guard let id else {
                records.removeValue(forKey: sessionID)
                suppressedSessions.insert(sessionID)
                return
            }
            records[sessionID]?.activityID = id
            startHeartbeatIfNeeded()
        } catch {
            if records[sessionID]?.token == token {
                records.removeValue(forKey: sessionID)
                suppressedSessions.insert(sessionID)
            }
        }
    }

    /// Ownership is cleared before any async work, so a late end cannot stop a
    /// replacement activity created for a new connection with the same session ID.
    @discardableResult
    public func sessionEnded(sessionID: UUID, reason: EndReason = .ended) -> Task<Void, Never>? {
        let record = records.removeValue(forKey: sessionID)
        suppressedSessions.remove(sessionID)
        stopHeartbeatIfIdle()
        guard let id = record?.activityID else { return nil }
        return endActivities([id], reason: reason)
    }

    /// Use scenePhase.background, not temporary inactive/LocalAuthentication UI.
    /// Ends display ownership; it deliberately never restarts a connection.
    @discardableResult
    public func applicationDidEnterBackground() -> Task<Void, Never>? {
        isForeground = false
        let ids = records.values.compactMap(\.activityID)
        records.removeAll()
        suppressedSessions.removeAll()
        heartbeat?.cancel()
        heartbeat = nil
        return endActivities(ids, reason: .backgrounded)
    }

    public func applicationWillEnterForeground() {
        isForeground = true
    }

    /// On a new process launch, sessions cannot have survived in-memory transport
    /// loss. Retire only orphan activities, never ones this controller just created.
    @discardableResult
    public func reconcileAfterLaunch() -> Task<Void, Never>? {
        let owned = Set(records.values.compactMap(\.activityID))
        let orphanIDs = driver.existingActivities().map(\.id).filter {
            !owned.contains($0) && !terminatingActivityIDs.contains($0)
        }
        return endActivities(orphanIDs, reason: .ended, immediately: true)
    }

    /// Only foreground activity is refreshed. staleDate lets the extension stop
    /// claiming a live connection after suspension, abrupt termination or a crash.
    public func refreshConnectedActivities() async {
        guard isForeground else { return }
        let liveIDs = Set(driver.existingActivities().map(\.id))
        let snapshot = records
        for (sessionID, record) in snapshot {
            guard isForeground, records[sessionID]?.token == record.token,
                  let id = record.activityID else { continue }
            guard liveIDs.contains(id) else {
                records.removeValue(forKey: sessionID)
                suppressedSessions.insert(sessionID)
                continue
            }
            let date = now()
            let driver = driver
            let staleDate = date.addingTimeInterval(staleInterval)
            let task = enqueue(id: id) {
                await driver.update(id: id, state: .init(phase: .connected, updatedAt: date),
                                    staleDate: staleDate)
            }
            await task.value
        }
        stopHeartbeatIfIdle()
    }

    @discardableResult
    private func endActivities(_ ids: [String], reason: EndReason,
                               immediately: Bool = false) -> Task<Void, Never>? {
        let ids = ids.filter { terminatingActivityIDs.insert($0).inserted }
        guard !ids.isEmpty else { return nil }
        let date = now()
        let state = SessionActivityContentState(phase: reason.phase, updatedAt: date)
        let dismissAt = immediately ? nil : date.addingTimeInterval(finalDisplayInterval)
        let driver = driver
        let lease = driver.beginTerminalTask()
        let tasks = ids.map { id in
            enqueue(id: id) { [weak self] in
                await driver.end(id: id, state: state, dismissAt: dismissAt)
                self?.terminatingActivityIDs.remove(id)
            }
        }
        return Task {
            defer { lease?.end() }
            for task in tasks { await task.value }
        }
    }

    /// An older foreground refresh must finish before the terminal update for
    /// that exact activity; replacements have a different ActivityKit ID.
    private func enqueue(id: String, operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let predecessor = operations[id]?.task
        let token = UUID()
        let task = Task { [weak self] in
            if let predecessor { await predecessor.value }
            await operation()
            if self?.operations[id]?.token == token {
                self?.operations.removeValue(forKey: id)
            }
        }
        operations[id] = Operation(token: token, task: task)
        return task
    }

    private func startHeartbeatIfNeeded() {
        guard heartbeat == nil, let interval = heartbeatInterval else { return }
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: interval) }
                catch { return }
                guard let self, self.isForeground, !self.records.isEmpty else { return }
                await self.refreshConnectedActivities()
            }
        }
    }

    private func stopHeartbeatIfIdle() {
        guard records.isEmpty else { return }
        heartbeat?.cancel()
        heartbeat = nil
    }
}
