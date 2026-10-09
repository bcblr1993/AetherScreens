import Foundation

/// Start-command framing from screensharingd. Paths stay byte strings until
/// negotiation establishes their encoding and destination semantics.
struct AppleFileCopyStart: Equatable, Sendable {
    enum Direction: Equatable, Sendable { case serverSends, serverReceives }
    enum Failure: Error, Equatable { case invalidBody }
    let direction: Direction
    let flags: UInt32
    let reserved: Data
    let path: Data
    let trailingBytes: Data

    /// Encodes only established framing. The negotiated owner supplies the raw
    /// path and options; this does not choose or authorize a remote destination.
    func message(sessionID: UInt32) throws -> AppleFileCopyMessage {
        guard reserved.count == 4, path.count <= Int(UInt16.max),
              !path.contains(0), trailingBytes.count <= 1_048_576 - 19 - path.count else {
            throw Failure.invalidBody
        }
        var body = Data()
        withUnsafeBytes(of: flags.bigEndian) { body.append(contentsOf: $0) }
        body.append(reserved)
        withUnsafeBytes(of: UInt16(path.count).bigEndian) { body.append(contentsOf: $0) }
        body.append(path)
        body.append(0)
        body.append(trailingBytes)
        return .init(version: 1, command: direction == .serverSends ? 1 : 2,
                     sessionID: sessionID, body: body)
    }

    static func decode(_ message: AppleFileCopyMessage, expectedSessionID: UInt32)
        throws -> Self? {
        guard message.version == 1, message.sessionID == expectedSessionID,
              message.command == 1 || message.command == 2 else { return nil }
        let bytes = [UInt8](message.body)
        guard bytes.count >= 11 else { throw Failure.invalidBody }
        let pathLength = Int(bytes[8]) << 8 | Int(bytes[9])
        let end = 10 + pathLength
        guard end < bytes.count, bytes[end] == 0,
              !bytes[10..<end].contains(0) else { throw Failure.invalidBody }
        let flags = bytes.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return Self(direction: message.command == 1 ? .serverSends : .serverReceives,
                    flags: flags, reserved: Data(bytes[4..<8]),
                    path: Data(bytes[10..<end]), trailingBytes: Data(bytes.dropFirst(end + 1)))
    }
}
