import Foundation
import CoreGraphics
import CoreImage
import CoreVideo
import Darwin

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
    private struct Change {
        let revision: UInt64
        let region: CGRect
    }
    private var revision: UInt64 = 0
    private var changes: [Change] = []
    private let retainedChangeCount = 64
    
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
        recordChange(CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
    }

    /// Update a dirty rectangle with Raw pixel data.
    public func updateRect(x: Int, y: Int, width: Int, height: Int, rawData: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard x >= 0, y >= 0, x < self.width, y < self.height,
              width > 0, height > 0, width <= Int.max / height / 4,
              rawData.count >= width * height * 4 else { return }
        let clippedWidth = min(width, self.width - x)
        let clippedHeight = min(height, self.height - y)
        rawData.withUnsafeBytes { source in
            pixels.withUnsafeMutableBytes { destination in
                guard let src = source.baseAddress, let dst = destination.baseAddress else { return }
                if x == 0 && width == self.width && clippedWidth == self.width {
                    memcpy(dst.advanced(by: y * self.width * 4), src, clippedWidth * clippedHeight * 4)
                } else {
                    for row in 0..<clippedHeight {
                        memcpy(dst.advanced(by: ((y + row) * self.width + x) * 4),
                               src.advanced(by: row * width * 4), clippedWidth * 4)
                    }
                }
            }
        }
        recordChange(CGRect(x: x, y: y, width: clippedWidth, height: clippedHeight))
    }

    /// Update dirty regions directly from a decoded `CVPixelBuffer` without allocating intermediate full-screen `Data`.
    public func updateFromPixelBuffer(
        _ pixelBuffer: CVPixelBuffer,
        dirtyRects: [(x: Int, y: Int, width: Int, height: Int)],
        fallbackContext: CIContext
    ) {
        let pbWidth = CVPixelBufferGetWidth(pixelBuffer)
        let pbHeight = CVPixelBufferGetHeight(pixelBuffer)
        guard pbWidth > 0, pbHeight > 0 else { return }

        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let effectiveRects = dirtyRects.isEmpty
            ? [(x: 0, y: 0, width: pbWidth, height: pbHeight)]
            : dirtyRects

        if format == kCVPixelFormatType_32BGRA {
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
            guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
            let srcBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

            lock.lock()
            defer { lock.unlock() }
            if width != pbWidth || height != pbHeight {
                width = pbWidth
                height = pbHeight
                pixels = [UInt8](repeating: 0, count: pbWidth * pbHeight * 4)
                recordChange(CGRect(x: 0, y: 0, width: pbWidth, height: pbHeight))
            }
            let dstBytesPerRow = width * 4
            pixels.withUnsafeMutableBytes { dstRaw in
                guard let dstBase = dstRaw.baseAddress else { return }
                for rect in effectiveRects {
                    let x0 = max(0, min(width, rect.x))
                    let y0 = max(0, min(height, rect.y))
                    let x1 = max(x0, min(width, rect.x + rect.width))
                    let y1 = max(y0, min(height, rect.y + rect.height))
                    let copyW = x1 - x0
                    let copyH = y1 - y0
                    guard copyW > 0, copyH > 0 else { continue }
                    if x0 == 0 && copyW == width && srcBytesPerRow == dstBytesPerRow {
                        let offset = y0 * dstBytesPerRow
                        memcpy(dstBase.advanced(by: offset), baseAddress.advanced(by: offset), copyH * dstBytesPerRow)
                    } else {
                        for row in y0..<y1 {
                            let srcPtr = baseAddress.advanced(by: row * srcBytesPerRow + x0 * 4)
                            let dstPtr = dstBase.advanced(by: row * dstBytesPerRow + x0 * 4)
                            memcpy(dstPtr, srcPtr, copyW * 4)
                        }
                    }
                    recordChange(CGRect(x: x0, y: y0, width: copyW, height: copyH))
                }
            }
            return
        }

        let ciImage = CIImage(cvImageBuffer: pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        lock.lock()
        defer { lock.unlock() }
        if width != pbWidth || height != pbHeight {
            width = pbWidth
            height = pbHeight
            pixels = [UInt8](repeating: 0, count: pbWidth * pbHeight * 4)
            recordChange(CGRect(x: 0, y: 0, width: pbWidth, height: pbHeight))
        }
        let dstBytesPerRow = width * 4
        pixels.withUnsafeMutableBytes { dstRaw in
            guard let dstBase = dstRaw.baseAddress else { return }
            fallbackContext.render(
                ciImage,
                toBitmap: dstBase,
                rowBytes: dstBytesPerRow,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                format: .BGRA8,
                colorSpace: colorSpace
            )
            for rect in effectiveRects {
                let x0 = max(0, min(width, rect.x))
                let y0 = max(0, min(height, rect.y))
                let x1 = max(x0, min(width, rect.x + rect.width))
                let y1 = max(y0, min(height, rect.y + rect.height))
                if x1 > x0 && y1 > y0 {
                    recordChange(CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))
                }
            }
        }
    }

    /// Copy with overlap-safe row order and no temporary allocation per row.
    public func copyRect(srcX: Int, srcY: Int, dstX: Int, dstY: Int, width: Int, height: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard srcX >= 0, srcY >= 0, dstX >= 0, dstY >= 0,
              srcX < self.width, dstX < self.width, srcY < self.height, dstY < self.height,
              width > 0, height > 0 else { return }
        let clippedWidth = min(width, self.width - max(srcX, dstX))
        let clippedHeight = min(height, self.height - max(srcY, dstY))
        pixels.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            for index in 0..<clippedHeight {
                let row = dstY > srcY ? clippedHeight - 1 - index : index
                memmove(base.advanced(by: ((dstY + row) * self.width + dstX) * 4),
                        base.advanced(by: ((srcY + row) * self.width + srcX) * 4), clippedWidth * 4)
            }
        }
        recordChange(CGRect(x: dstX, y: dstY, width: clippedWidth, height: clippedHeight))
    }

    private func recordChange(_ region: CGRect) {
        if revision == UInt64.max {
            revision = 0
            changes.removeAll(keepingCapacity: true)
            changes.append(Change(revision: 0, region: CGRect(x: 0, y: 0, width: width, height: height)))
        } else {
            revision += 1
            changes.append(Change(revision: revision, region: region))
        }
        if changes.count > retainedChangeCount { changes.removeFirst(changes.count - retainedChangeCount) }
    }

    /// Each texture keeps its own revision, so another renderer cannot consume its pending changes.
    /// Readers behind the bounded history receive the entire current image.
    func withPixelChanges(since previous: UInt64?, _ body: (UnsafeRawBufferPointer, Int, Int, [CGRect], UInt64) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        let regions: [CGRect]
        if let previous, previous == revision { regions = [] }
        else if let previous, previous < revision,
                let first = changes.first, first.revision == 0 || previous >= first.revision - 1 {
            var merged: [CGRect] = []
            for change in changes where change.revision > previous {
                var region = change.region.intersection(full)
                guard !region.isNull, !region.isEmpty else { continue }
                var index = 0
                while index < merged.count {
                    if region.insetBy(dx: -0.5, dy: -0.5).intersects(merged[index]) {
                        region = region.union(merged.remove(at: index))
                        index = 0
                    } else { index += 1 }
                }
                merged.append(region)
            }
            let changedArea = merged.reduce(CGFloat(0)) { $0 + $1.width * $1.height }
            regions = merged.count > 16 || changedArea >= full.width * full.height * 0.6 ? [full] : merged
        } else { regions = [full] }
        pixels.withUnsafeBytes { body($0, width, height, regions, revision) }
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
