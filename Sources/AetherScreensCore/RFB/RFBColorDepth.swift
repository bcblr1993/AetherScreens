import Foundation

/// Wire color precision. This changes pixel representation, never desktop size.
/// Lower precision can reduce payload size; compressed savings depend on content.
public enum RFBColorDepth: String, Codable, CaseIterable, Sendable {
    case fullColor
    case rgb565

    var pixelFormat: RFBPixelFormat {
        switch self {
        case .fullColor: return .standardBGRA32
        case .rgb565:
            return RFBPixelFormat(bitsPerPixel: 16, depth: 16, redMax: 31, greenMax: 63,
                                  blueMax: 31, redShift: 11, greenShift: 5, blueShift: 0)
        }
    }
    var bytesPerPixel: Int { self == .fullColor ? 4 : 2 }
    var compactBytesPerPixel: Int { self == .fullColor ? 3 : 2 }

    static func bgra565(_ value: UInt16) -> UInt32 {
        let blue = UInt32(value & 31) * 255 / 31
        let green = UInt32((value >> 5) & 63) * 255 / 63
        let red = UInt32((value >> 11) & 31) * 255 / 31
        return blue | green << 8 | red << 16 | 0xff000000
    }

    func expandPixels(_ data: Data) -> Data? {
        guard data.count % bytesPerPixel == 0 else { return nil }
        if self == .fullColor { return data }
        var output = Data(count: data.count * 2)
        data.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { destination in
                let input = source.bindMemory(to: UInt8.self)
                let pixels = destination.bindMemory(to: UInt8.self)
                for offset in stride(from: 0, to: input.count, by: 2) {
                    let color = Self.bgra565(UInt16(input[offset]) | UInt16(input[offset + 1]) << 8)
                    let target = offset * 2
                    pixels[target] = UInt8(truncatingIfNeeded: color)
                    pixels[target + 1] = UInt8(truncatingIfNeeded: color >> 8)
                    pixels[target + 2] = UInt8(truncatingIfNeeded: color >> 16)
                    pixels[target + 3] = 255
                }
            }
        }
        return output
    }
}
