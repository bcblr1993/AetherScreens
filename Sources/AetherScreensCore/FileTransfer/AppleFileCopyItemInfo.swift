import Foundation

/// Command 100 totals. Reported logical bytes are not proof of received bytes.
struct AppleFileCopyItemInfo: Equatable {
    enum Failure: Error { case invalidBody, exceedsLimit }
    /// The receiver byte-swaps this field; its meaning is not yet established.
    let rawHeaderValue: UInt32
    let reserved: Data
    let logicalBytes: UInt64
    let physicalBytes: UInt64
    let fileCount: UInt64
    let forkCount: UInt64
    let folderCount: UInt64
    let allocationSize: UInt32
    let trailing: Data

    /// Preserve the native sender's opaque flags and reserved bytes rather than
    /// deriving them from acknowledged transfer progress.
    func message(sessionID: UInt32, maximumPayloadBytes: Int = 1_048_576) throws -> AppleFileCopyMessage {
        guard reserved.count == 4 else { throw Failure.invalidBody }
        // Include the eight-byte common header before allocating the body.
        guard maximumPayloadBytes >= 60,
              trailing.count <= maximumPayloadBytes - 60,
              UInt64(trailing.count) <= UInt64(UInt32.max) - 60 else {
            throw Failure.exceedsLimit
        }
        var body = Data()
        body.reserveCapacity(52 + trailing.count)
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.bigEndian) { body.append(contentsOf: $0) }
        }
        append(rawHeaderValue)
        body.append(reserved)
        for value in [logicalBytes, physicalBytes, fileCount, forkCount, folderCount] {
            append(value)
        }
        append(allocationSize)
        body.append(trailing)
        return .init(version: 1, command: 100, sessionID: sessionID, body: body)
    }

    static func decode(_ message: AppleFileCopyMessage, expectedSessionID: UInt32) throws -> Self? {
        guard message.version == 1, message.command == 100,
              message.sessionID == expectedSessionID else { return nil }
        guard message.body.count >= 52 else { throw Failure.invalidBody }
        func u64(_ offset: Int) -> UInt64 {
            message.body.dropFirst(offset).prefix(8).reduce(0) { ($0 << 8) | UInt64($1) }
        }
        func u32(_ offset: Int) -> UInt32 {
            message.body.dropFirst(offset).prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
        }
        return .init(rawHeaderValue: u32(0), reserved: Data(message.body.dropFirst(4).prefix(4)),
            logicalBytes: u64(8), physicalBytes: u64(16), fileCount: u64(24),
            forkCount: u64(32), folderCount: u64(40), allocationSize: u32(48),
            trailing: Data(message.body.dropFirst(52)))
    }
}
