import Foundation

/// Lock Screen payloads never contain device names, endpoints, or credentials.
public enum SessionActivityPhase: String, Codable, Hashable, Sendable {
    case connected
    case paused
    case ended
    case failed
}

public struct SessionActivityContentState: Codable, Hashable, Sendable {
    public let phase: SessionActivityPhase
    public let updatedAt: Date

    public init(phase: SessionActivityPhase, updatedAt: Date) {
        self.phase = phase
        self.updatedAt = updatedAt
    }
}

/// Both the app and its extension import this single shared type.
public struct SessionActivityAttributes: Codable, Sendable {
    public typealias ContentState = SessionActivityContentState
    public let sessionID: UUID

    public init(sessionID: UUID) {
        self.sessionID = sessionID
    }
}

#if os(iOS) && canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit

extension SessionActivityAttributes: ActivityAttributes {}
#endif
