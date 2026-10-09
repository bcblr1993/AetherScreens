import Foundation
import zlib

/// Persistent stream decompressor for the RFB Zlib encoding extension (type 6).
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
        // Keep allocation bounded by actual streaming work rather than the
        // untrusted maximum, and reuse one scratch buffer for this payload.
        output.reserveCapacity(min(maximumBytes, 65_536))
        var chunk = Data(count: min(65_536, maximumBytes + 1))
        let success = data.withUnsafeBytes { input -> Bool in
            guard let base = input.baseAddress?.assumingMemoryBound(to: Bytef.self) else { return false }
            stream.next_in = UnsafeMutablePointer(mutating: base)
            stream.avail_in = uInt(data.count)
            defer { stream.next_in = nil; stream.next_out = nil }
            while true {
                // One extra byte detects an oversized expansion, even at a chunk boundary.
                let capacity = min(65_536, maximumBytes - output.count + 1)
                let previousInput = stream.avail_in
                let status = chunk.withUnsafeMutableBytes { buffer -> Int32 in
                    stream.next_out = buffer.baseAddress!.assumingMemoryBound(to: Bytef.self)
                    stream.avail_out = uInt(capacity)
                    return inflate(&stream, Z_SYNC_FLUSH)
                }
                let produced = capacity - Int(stream.avail_out)
                guard produced <= maximumBytes - output.count,
                      status == Z_OK || status == Z_STREAM_END || status == Z_BUF_ERROR else { return false }
                chunk.withUnsafeBytes { bytes in
                    output.append(contentsOf: bytes.prefix(produced))
                }
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

    /// Decode exactly one rectangle, consuming its entire compressed payload.
    public func decompress(data: Data, expectedBytes: Int) -> Data? {
        guard let output = decompress(data: data, maximumBytes: expectedBytes),
              output.count == expectedBytes else { return nil }
        return output
    }
}
