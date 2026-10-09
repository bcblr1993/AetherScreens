import Foundation
import NIOCore
import NIOPosix
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Retry only a session that has displayed a desktop, with a bounded budget.
struct SessionReconnectPolicy {
    private var established = false
    private var attempts = 0
    private var stopped = false
    private static let delays: [TimeInterval] = [1, 2, 4, 8, 16]

    mutating func receivedDesktop() {
        guard !stopped else { return }
        established = true
        attempts = 0
    }

    mutating func nextDelay() -> TimeInterval? {
        guard established, !stopped, attempts < Self.delays.count else { return nil }
        defer { attempts += 1 }
        return Self.delays[attempts]
    }

    mutating func stop() {
        stopped = true
        established = false
    }

    static func retriesSSHFailure(_ failure: SSHForwardingTunnel.Failure?) -> Bool {
        switch failure {
        case .closed, .timedOut: true
        default: false
        }
    }

    static func retriesSSHError(_ error: Error) -> Bool {
        if let failure = error as? SSHForwardingTunnel.Failure { return retriesSSHFailure(failure) }
        if let io = error as? IOError {
            return [ECONNREFUSED, ECONNRESET, ETIMEDOUT, EHOSTUNREACH, ENETUNREACH, ENETDOWN, EPIPE].contains(io.errnoCode)
        }
        if let channel = error as? ChannelError {
            switch channel {
            case .connectTimeout, .ioOnClosedChannel, .outputClosed, .inputClosed, .eof: return true
            default: return false
            }
        }
        if let connection = error as? NIOConnectionError {
            return !connection.connectionErrors.isEmpty && connection.connectionErrors.allSatisfy {
                // Bootstrap connection attempts contain socket errors, not authentication errors.
                guard let io = $0.error as? IOError else { return false }
                return retriesSSHError(io)
            }
        }
        return false
    }
}
