import Foundation

/// Offline command-body validation. The active fork and decompression stream
/// must be established by a negotiated item before these bytes can be written.
enum AppleFileCopyDataBlock: Equatable, Sendable {
    case raw(Data)
    case compressed(algorithm: UInt16, expandedBytes: UInt32, payload: Data)

    enum Failure: Error, Equatable {
        case invalidLength
        case exceedsFork
        case exceedsLimit
        case unsupportedCompression
    }

    static func decode(_ message: AppleFileCopyMessage, expectedSessionID: UInt32,
                       remainingForkBytes: UInt64, maximumExpandedBytes: Int = 1_048_576)
        throws -> Self? {
        guard message.sessionID == expectedSessionID,
              message.version == 1 || message.version == 2 else { return nil }
        guard message.command == 102 || message.command == 103 else { return nil }
        let bytes = [UInt8](message.body)
        let prefixLength = message.command == 102 ? 4 : 10
        guard bytes.count >= prefixLength else { throw Failure.invalidLength }
        func uint32(_ offset: Int) -> UInt32 {
            UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
                | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
        }
        let expanded = uint32(message.command == 102 ? 0 : 2)
        guard maximumExpandedBytes >= 0,
              UInt64(expanded) <= UInt64(maximumExpandedBytes) else {
            throw Failure.exceedsLimit
        }
        guard UInt64(expanded) <= remainingForkBytes else { throw Failure.exceedsFork }
        let payload = Data(bytes.dropFirst(prefixLength))
        if message.command == 102 {
            guard UInt64(payload.count) == UInt64(expanded) else { throw Failure.invalidLength }
            return .raw(payload)
        }
        let algorithm = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        guard algorithm == 1 else { throw Failure.unsupportedCompression }
        guard UInt64(payload.count) == UInt64(uint32(6)) else { throw Failure.invalidLength }
        return .compressed(algorithm: algorithm, expandedBytes: expanded, payload: payload)
    }
}
