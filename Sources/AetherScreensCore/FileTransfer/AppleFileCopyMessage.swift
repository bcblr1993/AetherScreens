import Foundation

/// Offline codec for the file-copy envelope observed in
/// screensharingd. Not advertised or sent by RFBClient until live negotiation
/// and the complete command grammar have been verified.
struct AppleFileCopyMessage: Equatable, Sendable {
    enum Failure: Error, Equatable {
        case unexpectedMessageType
        case invalidLength
        case exceedsLimit
    }

    let version: UInt16
    let command: UInt16
    let sessionID: UInt32
    let body: Data

    func encode(maximumPayloadBytes: Int = 1_048_576) throws -> Data {
        // Check before copying the body or narrowing its length to UInt32.
        guard maximumPayloadBytes >= 8, body.count <= maximumPayloadBytes - 8,
              UInt64(body.count) <= UInt64(UInt32.max) - 8 else {
            throw Failure.exceedsLimit
        }
        var packet = Data([0x22, 0])
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.bigEndian) { packet.append(contentsOf: $0) }
        }
        append(UInt32(body.count + 8))
        append(version)
        append(command)
        append(sessionID)
        packet.append(body)
        return packet
    }

    /// Returns nil for a partial frame. Consumed length lets callers retain the
    /// next frame without swallowing a coalesced RFB message.
    static func decode(_ data: Data, maximumPayloadBytes: Int = 1_048_576)
        throws -> (message: Self, consumedBytes: Int)? {
        guard let type = data.first else { return nil }
        guard type == 0x22 else { throw Failure.unexpectedMessageType }
        guard data.count >= 6 else { return nil }
        func byte(_ offset: Int) -> UInt32 {
            UInt32(data[data.index(data.startIndex, offsetBy: offset)])
        }
        func uint16(_ offset: Int) -> UInt16 {
            UInt16(byte(offset) << 8 | byte(offset + 1))
        }
        func uint32(_ offset: Int) -> UInt32 {
            byte(offset) << 24 | byte(offset + 1) << 16
                | byte(offset + 2) << 8 | byte(offset + 3)
        }
        let payloadLength = uint32(2)
        guard payloadLength >= 8 else { throw Failure.invalidLength }
        guard maximumPayloadBytes >= 8,
              UInt64(payloadLength) <= UInt64(maximumPayloadBytes) else {
            throw Failure.exceedsLimit
        }
        let frameLength = 6 + Int(payloadLength)
        guard data.count >= frameLength else { return nil }
        let bodyStart = data.index(data.startIndex, offsetBy: 14)
        let frameEnd = data.index(data.startIndex, offsetBy: frameLength)
        return (Self(version: uint16(6), command: uint16(8),
                     sessionID: uint32(10), body: Data(data[bodyStart..<frameEnd])),
                frameLength)
    }
}
