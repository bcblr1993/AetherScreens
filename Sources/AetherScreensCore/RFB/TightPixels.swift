import Foundation

/// Tight TPIXEL is RGB for our 24-bit true-color format, unlike ZRLE's BGR.
enum TightPixels {
    static let maximumOutputBytes = 256 * 1024 * 1024

    static func outputByteCount(width: Int, height: Int) -> Int? {
        guard width > 0, height > 0,
              width <= maximumOutputBytes / 4,
              height <= maximumOutputBytes / 4 / width else { return nil }
        return width * height * 4
    }

    static func expand(_ data: Data, colorDepth: RFBColorDepth) -> Data? {
        if colorDepth == .rgb565 {
            guard data.count <= maximumOutputBytes / 2 else { return nil }
            return colorDepth.expandPixels(data)
        }
        guard data.count % 3 == 0, data.count / 3 <= maximumOutputBytes / 4 else { return nil }
        var output = Data(count: data.count / 3 * 4)
        data.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { destination in
                let input = source.bindMemory(to: UInt8.self)
                let pixels = destination.bindMemory(to: UInt8.self)
                for offset in stride(from: 0, to: input.count, by: 3) {
                    let target = offset / 3 * 4
                    pixels[target] = input[offset + 2]
                    pixels[target + 1] = input[offset + 1]
                    pixels[target + 2] = input[offset]
                    pixels[target + 3] = 255
                }
            }
        }
        return output
    }

    static func fill(_ pixel: Data, width: Int, height: Int,
                     colorDepth: RFBColorDepth) -> Data? {
        guard pixel.count == colorDepth.compactBytesPerPixel,
              let byteCount = outputByteCount(width: width, height: height),
              let color = expand(pixel, colorDepth: colorDepth) else { return nil }
        var output = Data(count: byteCount)
        color.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { destination in
                let bytes = destination.bindMemory(to: UInt8.self)
                let rgba = source.bindMemory(to: UInt8.self)
                for offset in stride(from: 0, to: byteCount, by: 4) {
                    bytes[offset] = rgba[0]
                    bytes[offset + 1] = rgba[1]
                    bytes[offset + 2] = rgba[2]
                    bytes[offset + 3] = 255
                }
            }
        }
        return output
    }
}
