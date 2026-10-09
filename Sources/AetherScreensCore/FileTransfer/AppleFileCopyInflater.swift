import Foundation
import zlib

/// Experimental transfer-scoped inflater. Use on one transfer worker only;
/// it must never share the framebuffer decoder's dictionary.
final class AppleFileCopyInflater {
    enum Failure: Error, Equatable {
        case unavailable
        case exceedsLimit
        case invalidBlock
        case compression
    }

    private var stream = z_stream()
    private var initialized = false
    private var failed = false
    private let maximumBytes: Int

    init(maximumBytes: Int = 1_048_576) {
        self.maximumBytes = maximumBytes
        initialized = inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK
    }

    deinit { if initialized { inflateEnd(&stream) } }

    /// A malformed block invalidates this context. Create a fresh instance
    /// after verified transfer negotiation; do not silently reset mid-stream.
    func expand(_ block: AppleFileCopyDataBlock) throws -> Data {
        guard initialized, !failed else { throw Failure.unavailable }
        do {
            switch block {
            case .raw(let bytes):
                guard maximumBytes >= 0, bytes.count <= maximumBytes else { throw Failure.exceedsLimit }
                return bytes
            case .compressed(let algorithm, let expandedBytes, let payload):
                guard algorithm == 1, !payload.isEmpty,
                      payload.count <= Int(uInt.max) else { throw Failure.invalidBlock }
                guard maximumBytes >= 0, UInt64(expandedBytes) <= UInt64(maximumBytes),
                      expandedBytes < uInt.max else { throw Failure.exceedsLimit }
                // Native sender uses Z_SYNC_FLUSH, retaining its dictionary.
                // An extra output byte detects a dishonest declared size.
                var output = Data(count: Int(expandedBytes) + 1)
                let valid = payload.withUnsafeBytes { input in
                    output.withUnsafeMutableBytes { buffer -> Bool in
                        stream.next_in = UnsafeMutablePointer(mutating: input.baseAddress!.assumingMemoryBound(to: Bytef.self))
                        stream.avail_in = uInt(payload.count)
                        stream.next_out = buffer.baseAddress!.assumingMemoryBound(to: Bytef.self)
                        stream.avail_out = expandedBytes + 1
                        defer { stream.next_in = nil; stream.next_out = nil }
                        let status = inflate(&stream, Z_SYNC_FLUSH)
                        return status == Z_OK && stream.avail_in == 0
                            && stream.avail_out == 1
                            && payload.suffix(4) == Data([0, 0, 255, 255])
                    }
                }
                guard valid else { throw Failure.compression }
                output.removeLast()
                return output
            }
        } catch {
            failed = true
            throw error
        }
    }
}
