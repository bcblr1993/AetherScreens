import Foundation
import zlib

/// Experimental 0x450 codec. Confined to one session's decode queue; not yet
/// advertised. STORE RGB is treated as straight color pending live validation.
final class AppleCursorCache {
    enum Failure: Error { case malformed, limitExceeded, compression }
    static let maximumCompressedBytes = 2 * 1024 * 1024
    private let byteLimit: Int
    private let entryLimit: Int
    private var entries: [UInt32: RFBRemoteCursor] = [:]
    private var oldestFirst: [UInt32] = []
    private(set) var retainedBytes = 0
    var count: Int { entries.count }

    init(byteLimit: Int = 8 * 1024 * 1024, entryLimit: Int = 64) {
        self.byteLimit = max(0, byteLimit)
        self.entryLimit = max(0, entryLimit)
    }

    func reset() {
        entries.removeAll(); oldestFirst.removeAll(); retainedBytes = 0
    }

    /// A missing SELECT returns nil: callers preserve the last displayed shape.
    func decode(message: Data, width: Int, height: Int, hotspotX: Int,
                hotspotY: Int) throws -> RFBRemoteCursor? {
        guard message.count >= 8 else { throw Failure.malformed }
        let id = message.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
        let size = Int(message.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self).bigEndian })
        guard size <= Self.maximumCompressedBytes else { throw Failure.limitExceeded }
        guard message.count == 8 + size else { throw Failure.malformed }
        if size == 0 {
            guard width == 0, height == 0, hotspotX == 0, hotspotY == 0 else { throw Failure.malformed }
            guard let shape = entries[id] else { return nil }
            touch(id)
            return shape
        }
        guard width > 0, height > 0,
              width <= RFBRemoteCursor.maximumDimension, height <= RFBRemoteCursor.maximumDimension,
              (0..<width).contains(hotspotX), (0..<height).contains(hotspotY) else { throw Failure.malformed }
        let pixels = width * height
        let plain = try inflate(Data(message.dropFirst(8)), expected: pixels * 5)
        var bgra = Data(plain.prefix(pixels * 4))
        bgra.withUnsafeMutableBytes { output in
            plain.withUnsafeBytes { input in
                let dest = output.bindMemory(to: UInt8.self)
                let src = input.bindMemory(to: UInt8.self)
                for index in 0..<pixels {
                    let alpha = Int(src[pixels * 4 + index])
                    let base = index * 4
                    for channel in 0..<3 {
                        dest[base + channel] = UInt8((Int(src[base + channel]) * alpha + 127) / 255)
                    }
                    dest[base + 3] = UInt8(alpha)
                }
            }
        }
        let shape = RFBRemoteCursor(width: width, height: height, hotspotX: hotspotX,
                                   hotspotY: hotspotY, pixels: bgra)
        // A malformed replacement never changes the prior entry. A valid shape
        // can be displayed even if the configured budget prevents retaining it.
        remove(id)
        if entryLimit > 0, bgra.count <= byteLimit {
            while entries.count >= entryLimit || retainedBytes + bgra.count > byteLimit {
                guard let oldest = oldestFirst.first else { break }
                remove(oldest)
            }
            entries[id] = shape; retainedBytes += bgra.count; oldestFirst.append(id)
        }
        return shape
    }

    private func touch(_ id: UInt32) {
        oldestFirst.removeAll { $0 == id }; oldestFirst.append(id)
    }
    private func remove(_ id: UInt32) {
        if let old = entries.removeValue(forKey: id) { retainedBytes -= old.pixels.count }
        oldestFirst.removeAll { $0 == id }
    }

    private func inflate(_ data: Data, expected: Int) throws -> Data {
        var stream = z_stream()
        guard inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw Failure.compression }
        defer { inflateEnd(&stream) }
        var output = Data(count: expected + 1)
        let valid = data.withUnsafeBytes { input in
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
        guard valid else { throw Failure.compression }
        output.removeLast()
        return output
    }
}
