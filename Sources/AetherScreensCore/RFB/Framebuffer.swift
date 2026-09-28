import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#endif

/// Thread-safe in-memory framebuffer maintaining the decoded remote desktop state.
public final class Framebuffer: @unchecked Sendable {
    private let lock = NSLock()
    
    public private(set) var width: Int
    public private(set) var height: Int
    public private(set) var pixelFormat: RFBPixelFormat
    
    /// Raw bytes of the framebuffer in 32-bit (BGRA / RGBA) format.
    public private(set) var pixels: [UInt8]

    public init(width: Int = 1024, height: Int = 768, pixelFormat: RFBPixelFormat = .standardBGRA32) {
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
        let totalBytes = width * height * 4
        self.pixels = [UInt8](repeating: 0, count: totalBytes)
    }

    /// Resize the framebuffer (e.g. on DesktopSize pseudo-encoding).
    public func resize(newWidth: Int, newHeight: Int) {
        lock.lock()
        defer { lock.unlock() }

        guard newWidth > 0, newHeight > 0 else { return }
        self.width = newWidth
        self.height = newHeight
        let totalBytes = newWidth * newHeight * 4
        self.pixels = [UInt8](repeating: 0, count: totalBytes)
    }

    /// Update a dirty rectangle with Raw pixel data.
    public func updateRect(x: Int, y: Int, width: Int, height: Int, rawData: Data) {
        lock.lock()
        defer { lock.unlock() }

        let bpp = 4 // 32-bit BGRA
        let expectedBytes = width * height * bpp
        guard rawData.count >= expectedBytes else { return }

        let screenWidth = self.width
        let screenHeight = self.height

        rawData.withUnsafeBytes { rawPtr in
            guard let srcBase = rawPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }

            for row in 0..<height {
                let currentY = y + row
                guard currentY >= 0, currentY < screenHeight else { continue }

                let validWidth = min(width, max(0, screenWidth - x))
                guard validWidth > 0 else { continue }

                let srcOffset = row * width * bpp
                let dstOffset = (currentY * screenWidth + x) * bpp

                let src = srcBase.advanced(by: srcOffset)
                self.pixels.withUnsafeMutableBufferPointer { dstPtr in
                    guard let dstBase = dstPtr.baseAddress else { return }
                    let dst = dstBase.advanced(by: dstOffset)
                    dst.update(from: src, count: validWidth * bpp)
                }
            }
        }
    }

    /// Blit an existing rectangle to another location (CopyRect encoding).
    public func copyRect(srcX: Int, srcY: Int, dstX: Int, dstY: Int, width: Int, height: Int) {
        lock.lock()
        defer { lock.unlock() }

        let bpp = 4
        let screenWidth = self.width
        let screenHeight = self.height

        // Determine copying direction to avoid overwriting source
        let rowIndices: [Int] = (dstY > srcY) ? Array((0..<height).reversed()) : Array(0..<height)

        for row in rowIndices {
            let sy = srcY + row
            let dy = dstY + row
            guard sy >= 0, sy < screenHeight, dy >= 0, dy < screenHeight else { continue }

            let validWidth = min(width, screenWidth - max(srcX, dstX))
            guard validWidth > 0 else { continue }

            let srcOffset = (sy * screenWidth + srcX) * bpp
            let dstOffset = (dy * screenWidth + dstX) * bpp

            let slice = Array(pixels[srcOffset..<(srcOffset + validWidth * bpp)])
            pixels.replaceSubrange(dstOffset..<(dstOffset + validWidth * bpp), with: slice)
        }
    }

    /// Generates a CGImage snapshot of the current framebuffer state.
    public func makeCGImage() -> CGImage? {
        lock.lock()
        defer { lock.unlock() }

        guard width > 0, height > 0, pixels.count >= width * height * 4 else { return nil }

        let data = Data(pixels)
        guard let dataProvider = CGDataProvider(data: data as CFData) else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: CGBitmapInfo = [
            .byteOrder32Little,
            CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)
        ]

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// Gives the renderer a consistent pixel buffer while remote updates are paused.
    func withPixelBytes(_ body: (UnsafeRawBufferPointer, Int, Int) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        pixels.withUnsafeBytes { bytes in
            body(bytes, width, height)
        }
    }

    #if canImport(UIKit)
    public func makeUIImage() -> UIImage? {
        guard let cg = makeCGImage() else { return nil }
        return UIImage(cgImage: cg)
    }
    #elseif canImport(AppKit)
    public func makeNSImage() -> NSImage? {
        guard let cg = makeCGImage() else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: width, height: height))
    }
    #endif
}
