import Foundation

/// Command 104 ends the sender stream. This is distinct from the receiver's
/// command-200 result and does not authorize committing incomplete items.
enum AppleFileCopyEndSession: Equatable, Sendable {
    case resultAbsent
    case success
    // Preserve the native error bytes until numeric cross-version semantics
    // are verified. Zero/nonzero is independent of byte order.
    case failure(rawError: Data)

    enum Failure: Error, Equatable { case invalidBody }

    static func decode(_ message: AppleFileCopyMessage, expectedSessionID: UInt32) throws -> Self? {
        guard message.version == 1, message.command == 104,
              message.sessionID == expectedSessionID else { return nil }
        if message.body.isEmpty { return .resultAbsent }
        guard message.body.count == 4 else { throw Failure.invalidBody }
        return message.body.allSatisfy { $0 == 0 } ? .success : .failure(rawError: message.body)
    }
}
