import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Caches and persists desktop snapshot thumbnails for remote devices (Screens-style computer cards).
public final class ThumbnailStore: @unchecked Sendable {
    public static let shared = ThumbnailStore()

    private let memoryCache = NSCache<NSString, CGImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let lock = NSLock()

    public init() {
        let baseDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.cacheDirectory = baseDir
            .appendingPathComponent("AetherScreens", isDirectory: true)
            .appendingPathComponent("DesktopThumbnails", isDirectory: true)

        // TailScreens builds kept thumbnails directly under Caches; carry them over once.
        let legacyDirectory = baseDir.appendingPathComponent("DesktopThumbnails", isDirectory: true)
        if !fileManager.fileExists(atPath: cacheDirectory.path),
           fileManager.fileExists(atPath: legacyDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fileManager.moveItem(at: legacyDirectory, to: cacheDirectory)
        }

        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Retrieve the cached thumbnail for a device ID
    public func getThumbnail(for deviceId: UUID) -> CGImage? {
        let key = deviceId.uuidString as NSString

        lock.lock()
        if let cached = memoryCache.object(forKey: key) {
            lock.unlock()
            return cached
        }
        lock.unlock()

        // Try loading from disk
        let jpegURL = cacheDirectory.appendingPathComponent("\(deviceId.uuidString).jpg")
        let legacyURL = cacheDirectory.appendingPathComponent("\(deviceId.uuidString).png")
        guard let data = (try? Data(contentsOf: jpegURL)) ?? (try? Data(contentsOf: legacyURL)) else {
            return nil
        }

        #if canImport(UIKit)
        if let uiImg = UIImage(data: data), let cg = uiImg.cgImage {
            lock.lock()
            memoryCache.setObject(cg, forKey: key)
            lock.unlock()
            return cg
        }
        #elseif canImport(AppKit)
        if let nsImg = NSImage(data: data),
           let cg = nsImg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            lock.lock()
            memoryCache.setObject(cg, forKey: key)
            lock.unlock()
            return cg
        }
        #endif

        return nil
    }

    /// Save a new desktop thumbnail for a device ID
    public func saveThumbnail(_ image: CGImage, for deviceId: UUID) {
        let key = deviceId.uuidString as NSString
        let preview = scaledPreview(image)

        lock.lock()
        memoryCache.setObject(preview, forKey: key)
        lock.unlock()

        let fileURL = cacheDirectory.appendingPathComponent("\(deviceId.uuidString).jpg")

        #if canImport(UIKit)
        let uiImage = UIImage(cgImage: preview)
        if let pngData = uiImage.jpegData(compressionQuality: 0.75) {
            try? pngData.write(to: fileURL, options: .atomic)
        }
        #elseif canImport(AppKit)
        let rep = NSBitmapImageRep(cgImage: preview)
        if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.75]) {
            try? data.write(to: fileURL, options: .atomic)
        }
        #endif
    }

    private func scaledPreview(_ image: CGImage) -> CGImage {
        let maxWidth = 480
        guard image.width > maxWidth else { return image }
        let width = maxWidth
        let height = max(1, Int((Double(image.height) * Double(width) / Double(image.width)).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}
