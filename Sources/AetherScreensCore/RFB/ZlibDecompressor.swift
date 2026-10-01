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

    /// Inflate a variable-length tile stream without trusting a remote output size.
    /// ZRLE uses its own instance; its dictionary must not be shared with Zlib rectangles.
    func decompress(data: Data, maximumBytes: Int) -> Data? {
        guard isInitialized, !data.isEmpty, data.count <= Int(uInt.max),
              maximumBytes > 0, maximumBytes < Int.max else { return nil }
        var output = Data()
        let success = data.withUnsafeBytes { input -> Bool in
            guard let base = input.baseAddress?.assumingMemoryBound(to: Bytef.self) else { return false }
            stream.next_in = UnsafeMutablePointer(mutating: base)
            stream.avail_in = uInt(data.count)
            defer { stream.next_in = nil; stream.next_out = nil }
            while true {
                // One extra byte detects an oversized expansion, even at a chunk boundary.
                let capacity = min(65_536, maximumBytes - output.count + 1)
                var chunk = Data(count: capacity)
                let previousInput = stream.avail_in
                let status = chunk.withUnsafeMutableBytes { buffer -> Int32 in
                    stream.next_out = buffer.baseAddress!.assumingMemoryBound(to: Bytef.self)
                    stream.avail_out = uInt(capacity)
                    return inflate(&stream, Z_SYNC_FLUSH)
                }
                let produced = capacity - Int(stream.avail_out)
                guard produced <= maximumBytes - output.count,
                      status == Z_OK || status == Z_STREAM_END || status == Z_BUF_ERROR else { return false }
                output.append(chunk.prefix(produced))
                if status == Z_STREAM_END {
                    guard stream.avail_in == 0 else { return false }
                    inflateReset(&stream)
                    return true
                }
                if stream.avail_in == 0 && produced < capacity { return true }
                guard produced > 0 || stream.avail_in < previousInput else { return false }
            }
        }
        return success ? output : nil
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
