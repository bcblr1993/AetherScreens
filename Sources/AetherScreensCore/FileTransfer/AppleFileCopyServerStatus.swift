import Foundation

/// Status bodies observed in FileReceiveToolListenerThread. Parsing a status
/// does not establish that a transfer was negotiated or that bytes were saved.
enum AppleFileCopyServerStatus: Equatable, Sendable {
    case progress(fraction: Double)
    // Preserve name bytes until their encoding has been verified independently.
    case finished(errorCode: Int16, destinationName: Data)

    enum Failure: Error, Equatable {
        case invalidBody
        case invalidProgress
    }

    static func decode(_ message: AppleFileCopyMessage, expectedSessionID: UInt32)
        throws -> Self? {
        guard message.sessionID == expectedSessionID, message.version == 1 else { return nil }
        let bytes = [UInt8](message.body)
        switch message.command {
        case 300:
            guard bytes.count == 8 else { throw Failure.invalidBody }
            let bits = bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            let fraction = Double(bitPattern: bits)
            guard fraction.isFinite, (0...1).contains(fraction) else {
                throw Failure.invalidProgress
            }
            return .progress(fraction: fraction)
        case 200:
            guard bytes.count >= 5 else { throw Failure.invalidBody }
            let status = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            let nameLength = Int(UInt16(bytes[2]) << 8 | UInt16(bytes[3]))
            guard nameLength <= 1023, bytes.count == 5 + nameLength,
                  bytes.last == 0,
                  !bytes[4..<(4 + nameLength)].contains(0) else {
                throw Failure.invalidBody
            }
            return .finished(errorCode: Int16(bitPattern: status),
                             destinationName: Data(bytes[4..<(4 + nameLength)]))
        default:
            return nil
        }
    }
}
