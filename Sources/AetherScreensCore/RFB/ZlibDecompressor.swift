import Foundation
import zlib

/// Persistent stream decompressor for RFB Zlib encoding (RFC 6143 Section 7.7.5).
/// In RFB, a single continuous zlib stream is shared across all rectangles and updates.
public final class ZlibDecompressor: @unchecked Sendable {
    private var stream = z_stream()
    private var isInitialized = false

    public init() {
        let ret = inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        isInitialized = (ret == Z_OK)
    }

    deinit {
        if isInitialized {
            inflateEnd(&stream)
        }
    }

    public func reset() {
        if isInitialized {
            inflateReset(&stream)
        }
    }

    /// Decompresses `data` into expected uncompressed `expectedBytes`.
    public func decompress(data: Data, expectedBytes: Int) -> Data? {
        guard isInitialized, !data.isEmpty, expectedBytes > 0 else { return nil }

        var output = Data(count: expectedBytes)
        var producedBytes: Int?

        let success = data.withUnsafeBytes { inPtr -> Bool in
            guard let inBase = inPtr.baseAddress?.assumingMemoryBound(to: Bytef.self) else { return false }
            stream.next_in = UnsafeMutablePointer(mutating: inBase)
            stream.avail_in = uInt(data.count)

            return output.withUnsafeMutableBytes { outPtr -> Bool in
                guard let outBase = outPtr.baseAddress?.assumingMemoryBound(to: Bytef.self) else { return false }
                stream.next_out = outBase
                stream.avail_out = uInt(expectedBytes)

                let status = inflate(&stream, Z_SYNC_FLUSH)
                if status == Z_OK || status == Z_STREAM_END {
                    producedBytes = expectedBytes - Int(stream.avail_out)
                    if status == Z_STREAM_END {
                        inflateReset(&stream)
                    }
                    return true
                }
                return false
            }
        }

        if success, let produced = producedBytes {
            return output.prefix(produced)
        }
        return nil
    }
}
