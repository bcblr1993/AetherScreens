import Foundation
import zlib

/// Experimental Apple pasteboard archive codec. Call only with a fully
/// reassembled ClipboardSend body; encrypted-record boundaries are unrelated.
enum AppleClipboardArchive {
    enum Content: Equatable { case empty, text(String), unsupported, promise }
    enum Failure: Error { case malformed, limitExceeded, compression, invalidText }
    static let maximumBytes = 8 * 1024 * 1024

    static func encode(text: String) throws -> Data {
        let uti = Data("public.utf8-plain-text".utf8)
        let overhead = 20 + uti.count
        guard text.utf8.count <= maximumBytes - overhead else { throw Failure.limitExceeded }
        func word(_ value: Int) -> Data {
            var be = UInt32(value).bigEndian
            return withUnsafeBytes(of: &be) { Data($0) }
        }
        let bytes = Data(text.utf8)
        let plain = word(1) + word(uti.count) + uti + word(0) + word(0) + word(bytes.count) + bytes
        var stream = z_stream()
        guard deflateInit_(&stream, Z_DEFAULT_COMPRESSION, ZLIB_VERSION,
                          Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw Failure.compression }
        defer { deflateEnd(&stream) }
        let capacity = min(Int(compressBound(uLong(plain.count))) + 16, maximumBytes + 1)
        var compressed = Data(count: capacity)
        let success = plain.withUnsafeBytes { input in
            compressed.withUnsafeMutableBytes { output -> Bool in
                stream.next_in = UnsafeMutablePointer(mutating: input.baseAddress!.assumingMemoryBound(to: Bytef.self))
                stream.avail_in = uInt(plain.count)
                stream.next_out = output.baseAddress!.assumingMemoryBound(to: Bytef.self)
                stream.avail_out = uInt(capacity)
                return deflate(&stream, Z_SYNC_FLUSH) == Z_OK && stream.avail_in == 0 && stream.avail_out > 0
            }
        }
        guard success, stream.total_out <= maximumBytes else { throw Failure.compression }
        compressed.count = Int(stream.total_out)
        return Data([31, 0, 0, 0, 0, 0, 0, 0]) + word(plain.count) + word(compressed.count) + compressed
    }

    static func decode(message: Data) throws -> Content {
        guard message.count >= 16, message.count <= maximumBytes + 16 else { throw Failure.limitExceeded }
        var reader = Reader(data: message)
        guard try reader.take(1).first == 0x1f else { throw Failure.malformed }
        let flags = try reader.take(7) // padding, promise and reserved fields
        let promise = flags[flags.startIndex + 1]
        guard promise <= 1 else { throw Failure.malformed }
        let plainSize = try reader.integer()
        let compressedSize = try reader.integer()
        guard plainSize <= maximumBytes, compressedSize <= maximumBytes else { throw Failure.limitExceeded }
        guard compressedSize == reader.remaining else { throw Failure.malformed }
        let compressed = try reader.take(compressedSize)
        let content = try parse(inflate(compressed, expected: plainSize))
        // A metadata-only reply must never overwrite/clear a local pasteboard.
        return promise == 1 ? .promise : content
    }

    static func parse(_ data: Data) throws -> Content {
        guard data.count <= maximumBytes else { throw Failure.limitExceeded }
        if data.isEmpty { return .empty }
        var reader = Reader(data: data)
        let count = try reader.integer()
        guard count <= 64 else { throw Failure.limitExceeded }
        var utf8: String?, utf16: String?
        for _ in 0..<count {
            let uti = try reader.string(limit: 1024)
            _ = try reader.integer() // reserved: tolerate unknown values
            let aliases = try reader.integer()
            guard aliases <= 32 else { throw Failure.limitExceeded }
            for _ in 0..<aliases {
                _ = try reader.blob(limit: 4096)
                _ = try reader.blob(limit: 4096)
            }
            let bytes = try reader.blob(limit: maximumBytes)
            if uti == "public.utf8-plain-text" {
                guard let text = String(data: bytes, encoding: .utf8) else { throw Failure.invalidText }
                if utf8 == nil { utf8 = text }
            } else if uti == "public.utf16-plain-text" {
                guard bytes.count % 2 == 0, let text = String(data: bytes, encoding: .utf16BigEndian),
                      Data(text.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 255)] }) == bytes else { throw Failure.invalidText }
                if utf16 == nil { utf16 = text }
            }
        }
        guard reader.remaining == 0 else { throw Failure.malformed }
        if let text = utf8 ?? utf16 { return .text(text) }
        return count == 0 ? .empty : .unsupported
    }

    private static func inflate(_ data: Data, expected: Int) throws -> Data {
        guard !data.isEmpty else { throw Failure.compression }
        var stream = z_stream()
        guard inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw Failure.compression }
        defer { inflateEnd(&stream) }
        // One extra byte detects size under-reporting without unbounded inflation.
        var output = Data(count: expected + 1)
        let success = data.withUnsafeBytes { input in
            output.withUnsafeMutableBytes { buffer -> Bool in
                stream.next_in = UnsafeMutablePointer(mutating: input.baseAddress!.assumingMemoryBound(to: Bytef.self))
                stream.avail_in = uInt(data.count)
                stream.next_out = buffer.baseAddress!.assumingMemoryBound(to: Bytef.self)
                stream.avail_out = uInt(expected + 1)
                let status = zlib.inflate(&stream, Z_SYNC_FLUSH)
                let complete = status == Z_STREAM_END ||
                    (status == Z_OK && data.suffix(4) == Data([0, 0, 255, 255]))
                return complete && stream.avail_in == 0 && stream.total_out == expected
            }
        }
        guard success else { throw Failure.compression }
        output.removeLast()
        return output
    }

    private struct Reader {
        let data: Data
        var offset = 0
        var remaining: Int { data.count - offset }
        mutating func take(_ size: Int) throws -> Data {
            guard size >= 0, size <= remaining else { throw Failure.malformed }
            let start = data.startIndex + offset
            offset += size
            return data.subdata(in: start..<(start + size))
        }
        mutating func integer() throws -> Int {
            Int(try take(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        }
        mutating func blob(limit: Int) throws -> Data {
            let size = try integer()
            guard size <= limit else { throw Failure.limitExceeded }
            return try take(size)
        }
        mutating func string(limit: Int) throws -> String {
            guard let text = String(data: try blob(limit: limit), encoding: .utf8) else { throw Failure.malformed }
            return text
        }
    }
}

/// Session-local assembler for one ClipboardSend message. The transport must
/// supply only that message's continuation bytes and enforce its own deadline.
final class AppleClipboardAssembler {
    private var pending = Data()
    private var expectedSize: Int?

    func reset() { pending = Data(); expectedSize = nil }

    func append(_ fragment: Data) throws -> AppleClipboardArchive.Content? {
        do {
            guard !fragment.isEmpty,
                  fragment.count <= AppleClipboardArchive.maximumBytes + 16 - pending.count else {
                throw AppleClipboardArchive.Failure.limitExceeded
            }
            pending.append(fragment)
            if expectedSize == nil, pending.count >= 16 {
                guard pending.first == 0x1f else { throw AppleClipboardArchive.Failure.malformed }
                let plain = pending[8..<12].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
                let compressed = pending[12..<16].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
                guard plain <= AppleClipboardArchive.maximumBytes,
                      compressed > 0, compressed <= AppleClipboardArchive.maximumBytes else {
                    throw AppleClipboardArchive.Failure.limitExceeded
                }
                expectedSize = 16 + Int(compressed)
            }
            guard let expectedSize else { return nil }
            guard pending.count <= expectedSize else { throw AppleClipboardArchive.Failure.malformed }
            guard pending.count == expectedSize else { return nil }
            let content = try AppleClipboardArchive.decode(message: pending)
            reset()
            return content
        } catch {
            reset()
            throw error
        }
    }
}
