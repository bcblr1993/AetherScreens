import Foundation
import AetherScreensWidgetSupport

#if os(iOS) && canImport(ActivityKit) && !targetEnvironment(macCatalyst) && !AETHERSCREENS_QA_ISOLATION
import ActivityKit
import UIKit

@MainActor
struct SystemSessionActivityDriver: SessionActivityDriver {
    var canStart: Bool {
        UIApplication.shared.applicationState == .active && ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func existingActivities() -> [SessionActivityReference] {
        Activity<SessionActivityAttributes>.activities.compactMap { activity in
            guard activity.activityState == .active || activity.activityState == .stale else { return nil }
            return .init(id: activity.id, sessionID: activity.attributes.sessionID)
        }
    }

    func start(sessionID: UUID, state: SessionActivityContentState, staleDate: Date) throws -> String? {
        guard canStart else { return nil }
        return try Activity<SessionActivityAttributes>.request(
            attributes: .init(sessionID: sessionID),
            content: .init(state: state, staleDate: staleDate), pushType: nil
        ).id
    }

    func update(id: String, state: SessionActivityContentState, staleDate: Date) async {
        guard let activity = activity(id) else { return }
        await activity.update(.init(state: state, staleDate: staleDate))
    }

    func end(id: String, state: SessionActivityContentState, dismissAt: Date?) async {
        guard let activity = activity(id) else { return }
        await activity.end(.init(state: state, staleDate: nil),
                           dismissalPolicy: dismissAt.map { ActivityUIDismissalPolicy.after($0) } ?? .immediate)
    }

    func beginTerminalTask() -> (any SessionActivityCleanupLease)? {
        SessionActivityBackgroundTask.begin()
    }

    private func activity(_ id: String) -> Activity<SessionActivityAttributes>? {
        Activity<SessionActivityAttributes>.activities.first { $0.id == id }
    }
}

/// A short cleanup assertion only; it never owns or extends the VNC session.
@MainActor
private final class SessionActivityBackgroundTask: SessionActivityCleanupLease {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private var hasEnded = false
    private var deadline: Task<Void, Never>?

    static func begin() -> SessionActivityBackgroundTask? {
        let task = SessionActivityBackgroundTask()
        let identifier = UIApplication.shared.beginBackgroundTask(withName: "End remote session activity") { [weak task] in
            task?.end()
        }
        task.identifier = identifier
        // UIKit may invoke expiration synchronously while requesting the lease.
        if task.hasEnded {
            if identifier != .invalid { UIApplication.shared.endBackgroundTask(identifier) }
            task.identifier = .invalid
            return nil
        }
        guard identifier != .invalid else { return nil }
        task.deadline = Task { [weak task] in
            do { try await Task.sleep(nanoseconds: 30_000_000_000) }
            catch { return }
            task?.end()
        }
        return task
    }

    func end() {
        guard !hasEnded else { return }
        hasEnded = true
        deadline?.cancel()
        deadline = nil
        let identifier = identifier
        self.identifier = .invalid
        if identifier != .invalid { UIApplication.shared.endBackgroundTask(identifier) }
    }
}
#else
/// macOS and controlled UI isolation never contact the ActivityKit service.
@MainActor
struct SystemSessionActivityDriver: SessionActivityDriver {
    var canStart: Bool { false }
    func existingActivities() -> [SessionActivityReference] { [] }
    func start(sessionID: UUID, state: SessionActivityContentState, staleDate: Date) throws -> String? { nil }
    func update(id: String, state: SessionActivityContentState, staleDate: Date) async {}
    func end(id: String, state: SessionActivityContentState, dismissAt: Date?) async {}
}
#endif
