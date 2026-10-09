import Foundation
import CoreGraphics

/// Session-local cursor with premultiplied BGRA. Standard mask pixels have
/// alpha 0/255; vendor alpha planes may have partial opacity. A zero dimension
/// explicitly hides the cursor.
public struct RFBRemoteCursor: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let hotspotX: Int
    public let hotspotY: Int
    public let pixels: Data
    private let cachedImage: CGImage?
    public var isHidden: Bool { width == 0 || height == 0 }
    static let maximumDimension = 512

    static func payloadSize(width: Int, height: Int, depth: RFBColorDepth) -> Int? {
        guard width >= 0, height >= 0 else { return nil }
        if width == 0 || height == 0 { return 0 }
        guard width <= maximumDimension, height <= maximumDimension else { return nil }
        return width * height * depth.bytesPerPixel + ((width + 7) / 8) * height
    }

    static func decode(width: Int, height: Int, hotspotX: Int, hotspotY: Int,
                       depth: RFBColorDepth, payload: Data) -> RFBRemoteCursor? {
        guard let size = payloadSize(width: width, height: height, depth: depth), payload.count == size else { return nil }
        if width == 0 || height == 0 {
            return RFBRemoteCursor(width: 0, height: 0, hotspotX: 0, hotspotY: 0, pixels: Data())
        }
        guard (0..<width).contains(hotspotX), (0..<height).contains(hotspotY) else { return nil }
        let pixelCount = width * height
        let wireBytes = pixelCount * depth.bytesPerPixel
        guard var pixels = depth.expandPixels(Data(payload.prefix(wireBytes))) else { return nil }
        let mask = Array(payload.suffix(size - wireBytes))
        let stride = (width + 7) / 8
        pixels.withUnsafeMutableBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let target = (y * width + x) * 4
                    if mask[y * stride + x / 8] & UInt8(0x80 >> (x % 8)) == 0 {
                        bytes[target] = 0; bytes[target + 1] = 0; bytes[target + 2] = 0; bytes[target + 3] = 0
                    } else { bytes[target + 3] = 255 }
                }
            }
        }
        return RFBRemoteCursor(width: width, height: height, hotspotX: hotspotX, hotspotY: hotspotY, pixels: pixels)
    }

    init(width: Int, height: Int, hotspotX: Int, hotspotY: Int, pixels: Data) {
        self.width = width; self.height = height
        self.hotspotX = hotspotX; self.hotspotY = hotspotY; self.pixels = pixels
        if width > 0, height > 0, width <= Self.maximumDimension, height <= Self.maximumDimension,
           pixels.count == width * height * 4, let provider = CGDataProvider(data: pixels as CFData) {
            cachedImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
                    .union(.byteOrder32Little), provider: provider, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent)
        } else { cachedImage = nil }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.width == rhs.width && lhs.height == rhs.height && lhs.hotspotX == rhs.hotspotX &&
        lhs.hotspotY == rhs.hotspotY && lhs.pixels == rhs.pixels
    }

    /// Decode workers construct the immutable image once; native views reuse it.
    public func makeCGImage() -> CGImage? { cachedImage }
}
