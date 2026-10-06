import Foundation

/// Server metadata confirms console visibility, not the appearance of the
/// physical display. In particular, a lock surface is not proof of a black screen.
public struct RFBCurtainStatus: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case disconnected, unavailable, ready, hiding, hidden, restoring, visible
        case timedOut, failed, unknown
    }
    public let connectionID: UUID?
    public let phase: Phase
    public let canRequest: Bool
    public let needsRestoration: Bool
    public let recoveryUnconfirmed: Bool
    public var isPending: Bool { phase == .hiding || phase == .restoring }
    public var isConfirmedHidden: Bool { phase == .hidden }
    public static let disconnected = Self(connectionID: nil, phase: .disconnected,
                                          canRequest: false, needsRestoration: false, recoveryUnconfirmed: false)
}

/// Read-only transport snapshot. The client revision survives reconnects; the
/// confirmation identity exists only after fresh metadata settles that restore.
final class RFBCurtainEventSource: Equatable, @unchecked Sendable {
    let id = UUID()
    private let lock = NSLock()
    private var acceptedRevision: UInt64 = 0

    /// The recovery consumer lives outside windows, but replay protection belongs
    /// to the source lifetime. Closed sources need no permanent ledger tombstone.
    func accept(_ revision: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard revision > acceptedRevision else { return false }
        acceptedRevision = revision
        return true
    }

    static func == (lhs: RFBCurtainEventSource, rhs: RFBCurtainEventSource) -> Bool { lhs === rhs }
}

struct RFBCurtainEvent: Equatable, Sendable {
    let source: RFBCurtainEventSource
    var sourceID: UUID { source.id }
    let revision: UInt64
    let account: String?
    let transportAttached: Bool
    let status: RFBCurtainStatus
    let pendingRequestID: UUID?
    let pendingHidden: Bool?
    let confirmedRestorationID: UUID?
}

/// A pure reducer. The transport supplies authenticated connection identity,
/// accepted version-5 DisplayInfo2 metadata and timer/send outcomes under its lock.
/// No initial non-console state, old connection or local toggle is a confirmation.
struct RFBAppleCurtain {
    struct Request: Equatable, Sendable {
        let id: UUID
        let connectionID: UUID
        let hidden: Bool
        let afterMetadata: UInt64
    }
    private(set) var status = RFBCurtainStatus.disconnected
    private(set) var pending: Request?
    private(set) var confirmedRestorationID: UUID?
    private var connectionID: UUID?
    private var authenticatedApple = false
    private var flags: UInt32?
    private var metadataRevision: UInt64 = 0
    private var recoveryUnconfirmed = false
    var hasConnection: Bool { connectionID != nil }

    mutating func beginConnection(_ id: UUID) {
        connectionID = id
        authenticatedApple = false
        flags = nil
        metadataRevision = 0
        pending = nil
        confirmedRestorationID = nil
        publish(.unavailable, needsRestoration: false)
    }

    /// A new authenticated account has its own recovery scope. The process-local
    /// ledger retains other accounts' warnings independently of this connection.
    mutating func configureRecoveryForNewConnection(_ unconfirmed: Bool) {
        guard !authenticatedApple, pending == nil, !status.needsRestoration else { return }
        recoveryUnconfirmed = unconfirmed
        publish(status.phase, needsRestoration: false)
    }

    mutating func inheritRecoveryWarning() {
        guard !recoveryUnconfirmed else { return }
        recoveryUnconfirmed = true
        publish(status.phase, needsRestoration: status.needsRestoration)
    }

    mutating func authenticated(connection id: UUID, apple: Bool) {
        guard connectionID == id else { return }
        authenticatedApple = apple
        publish(.unavailable, needsRestoration: false)
    }

    private var supportsRequest: Bool {
        guard authenticatedApple, let flags else { return false }
        return flags & 0x02 != 0 && flags & 0x18 == 0
    }

    mutating func metadata(connection id: UUID, version: UInt16 = 5, sessionFlags: UInt32) {
        guard connectionID == id, authenticatedApple else { return }
        metadataRevision &+= 1
        flags = version == 5 ? sessionFlags : nil
        let onConsole = sessionFlags & 0x04 != 0
        if let request = pending {
            guard supportsRequest else {
                pending = nil
                publish(.unknown, needsRestoration: status.needsRestoration)
                return
            }
            // An opposite or unchanged report keeps waiting; only a new report
            // after this request with usable capability/login flags can settle it.
            if metadataRevision > request.afterMetadata, onConsole == !request.hidden {
                pending = nil
                if !request.hidden {
                    recoveryUnconfirmed = false
                    confirmedRestorationID = request.id
                }
                publish(request.hidden ? .hidden : .visible, needsRestoration: request.hidden)
            }
            return
        }
        if status.needsRestoration {
            if supportsRequest, onConsole {
                publish(.visible, needsRestoration: false)
            } else if !supportsRequest {
                publish(.unknown, needsRestoration: true)
            }
            return
        }
        publish(supportsRequest ? (onConsole ? .ready : .unknown) : .unavailable,
                needsRestoration: false)
    }

    mutating func request(hidden: Bool, id: UUID = UUID()) -> Request? {
        guard supportsRequest, let connectionID, pending == nil else { return nil }
        let request = Request(id: id, connectionID: connectionID, hidden: hidden,
                              afterMetadata: metadataRevision)
        pending = request
        confirmedRestorationID = nil
        // Even a failed/partial hide write may have reached the server.
        publish(hidden ? .hiding : .restoring,
                needsRestoration: hidden || status.needsRestoration || recoveryUnconfirmed)
        return request
    }

    /// A restore supersedes an in-flight hide when closing the same connection.
    /// Capability and login gating still applies; it never acts on a new socket.
    mutating func restorationForClose() -> Request? {
        guard status.needsRestoration else { return nil }
        pending = nil
        return request(hidden: false)
    }

    mutating func expire(_ request: Request) {
        guard pending == request, connectionID == request.connectionID else { return }
        pending = nil
        publish(.timedOut, needsRestoration: status.needsRestoration)
    }

    @discardableResult
    mutating func writeFailed(_ request: Request) -> Bool {
        guard pending == request, connectionID == request.connectionID else { return false }
        pending = nil
        publish(.failed, needsRestoration: status.needsRestoration)
        return true
    }

    mutating func disconnected(connection id: UUID, failed: Bool = false) {
        guard connectionID == id else { return }
        let unresolved = status.needsRestoration
        recoveryUnconfirmed = recoveryUnconfirmed || unresolved
        pending = nil
        authenticatedApple = false
        flags = nil
        publish(unresolved ? .unknown : (failed ? .failed : .disconnected), needsRestoration: unresolved)
        connectionID = nil
    }

    private mutating func publish(_ phase: RFBCurtainStatus.Phase, needsRestoration: Bool) {
        status = .init(connectionID: connectionID, phase: phase,
                       canRequest: supportsRequest, needsRestoration: needsRestoration,
                       recoveryUnconfirmed: recoveryUnconfirmed)
    }
}
