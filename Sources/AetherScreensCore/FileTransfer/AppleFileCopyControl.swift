import Foundation

/// Header-only controls dispatched by the inspected native server. The owner
/// must stop its local worker too; a queued stop is not remote cancellation proof.
enum AppleFileCopyControl: UInt16, Sendable {
    case pause = 3
    case resume = 4
    case stop = 5

    func message(sessionID: UInt32) -> AppleFileCopyMessage {
        .init(version: 1, command: rawValue, sessionID: sessionID, body: Data())
    }

    static func decode(_ message: AppleFileCopyMessage, expectedSessionID: UInt32) -> Self? {
        guard message.version == 1, message.sessionID == expectedSessionID,
              message.body.isEmpty else { return nil }
        return Self(rawValue: message.command)
    }
}
