import Foundation

/// RFC 6143 section 7.7.6, for the 32-bit little-endian BGRA format requested by RFBClient.
/// Tile data uses three-byte BGR pixels; decoded output is opaque four-byte BGRA.
/// RFBClient confines dictionary access and reset to its serial connection queue.
final class ZRLEDecoder {
    private let decompressor = ZlibDecompressor()
    static let maximumPixelBytes = 256 * 1024 * 1024

    func reset() { decompressor.reset() }

    static func maximumTileBytes(width: Int, height: Int) -> Int? {
        guard width > 0, height > 0, width <= maximumPixelBytes / 4 / height else { return nil }
        let tiles = ((width + 63) / 64) * ((height + 63) / 64)
        // Plain RLE needs at most four bytes per pixel; each tile can also carry
        // a 127-entry three-byte palette and its subencoding byte.
        return width * height * 4 + tiles * 384
    }

    func decode(data: Data, width: Int, height: Int) -> Data? {
        guard let maximum = Self.maximumTileBytes(width: width, height: height),
              data.count <= maximum * 2 + 1024,
              let tiles = decompressor.decompress(data: data, maximumBytes: maximum) else { return nil }
        // Typed allocation guarantees pixel alignment, including tiny rectangles;
        // Data's inline byte storage is not a typed pixel allocation.
        let output = UnsafeMutableBufferPointer<UInt32>.allocate(capacity: width * height)
        output.initialize(repeating: 0)
        let valid = tiles.withUnsafeBytes { source -> Bool in
            var reader = TileReader(bytes: source.bindMemory(to: UInt8.self))
            do {
                for y in stride(from: 0, to: height, by: 64) {
                    for x in stride(from: 0, to: width, by: 64) {
                        let tileWidth = min(64, width - x), tileHeight = min(64, height - y)
                        let count = tileWidth * tileHeight
                        let type = Int(try reader.byte())
                        var position = 0
                        func write(_ color: UInt32, length: Int) {
                            var remaining = length
                            while remaining > 0 {
                                let row = position / tileWidth, column = position % tileWidth
                                let span = min(remaining, tileWidth - column)
                                output.baseAddress!.advanced(by: (y + row) * width + x + column)
                                    .update(repeating: color.littleEndian, count: span)
                                position += span
                                remaining -= span
                            }
                        }
                        switch type {
                        case 0:
                            // Validate a complete compact-pixel tile once, then expand it
                            // without three throwing byte reads for every pixel.
                            let compact = try reader.take(count * 3)
                            for row in 0..<tileHeight {
                                let start = (y + row) * width + x
                                for column in 0..<tileWidth {
                                    let index = (row * tileWidth + column) * 3
                                    let color = UInt32(compact[index]) | UInt32(compact[index + 1]) << 8
                                        | UInt32(compact[index + 2]) << 16 | 0xff000000
                                    output[start + column] = color.littleEndian
                                }
                            }
                        case 1:
                            write(try reader.pixel(), length: count)
                        case 2...16:
                            let palette = try reader.palette(size: type)
                            let bits = type == 2 ? 1 : (type <= 4 ? 2 : 4)
                            let rowBytes = (tileWidth * bits + 7) / 8
                            for row in 0..<tileHeight {
                                let start = (y + row) * width + x
                                for packedIndex in 0..<rowBytes {
                                    let packed = Int(try reader.byte())
                                    for field in 0..<(8 / bits) where packedIndex * (8 / bits) + field < tileWidth {
                                        let index = (packed >> (8 - bits * (field + 1))) & ((1 << bits) - 1)
                                        guard index < palette.count else { throw TileError.invalid }
                                        let column = packedIndex * (8 / bits) + field
                                        output[start + column] = palette[index].littleEndian
                                    }
                                }
                            }
                        case 128:
                            while position < count {
                                let color = try reader.pixel()
                                write(color, length: try reader.runLength(remaining: count - position))
                            }
                        case 130...255:
                            let palette = try reader.palette(size: type - 128)
                            while position < count {
                                let code = Int(try reader.byte()), index = code & 127
                                guard index < palette.count else { throw TileError.invalid }
                                let length = code & 128 == 0 ? 1 : try reader.runLength(remaining: count - position)
                                write(palette[index], length: length)
                            }
                        default: throw TileError.invalid
                        }
                    }
                }
                return reader.offset == reader.bytes.count
            } catch { return false }
        }
        guard valid else { output.deallocate(); return nil }
        return Data(bytesNoCopy: output.baseAddress!, count: output.count * 4,
                    deallocator: .custom { pointer, _ in pointer.deallocate() })
    }

    private enum TileError: Error { case invalid }
    private struct TileReader {
        let bytes: UnsafeBufferPointer<UInt8>
        var offset = 0
        mutating func take(_ count: Int) throws -> UnsafeBufferPointer<UInt8> {
            guard count >= 0, count <= bytes.count - offset else { throw TileError.invalid }
            let end = offset + count
            defer { offset = end }
            return UnsafeBufferPointer(rebasing: bytes[offset..<end])
        }
        mutating func byte() throws -> UInt8 {
            guard offset < bytes.count else { throw TileError.invalid }
            defer { offset += 1 }
            return bytes[offset]
        }
        mutating func pixel() throws -> UInt32 {
            let blue = UInt32(try byte()), green = UInt32(try byte()), red = UInt32(try byte())
            return blue | green << 8 | red << 16 | 0xff000000
        }
        mutating func palette(size: Int) throws -> [UInt32] {
            try (0..<size).map { _ in try pixel() }
        }
        mutating func runLength(remaining: Int) throws -> Int {
            var length = 1
            while true {
                let part = Int(try byte())
                guard part <= remaining - length else { throw TileError.invalid }
                length += part
                if part != 255 { return length }
            }
        }
    }
}
