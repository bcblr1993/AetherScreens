import Foundation
import CoreGraphics
import ImageIO
import Combine

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
    private var removedIDs = Set<UUID>()
    private let loadingQueue: DispatchQueue
    private final class LoadCancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool {
            lock.lock(); defer { lock.unlock() }
            return cancelled
        }
        func cancel() {
            lock.lock(); defer { lock.unlock() }
            cancelled = true
        }
    }
    private let changes = PassthroughSubject<UUID, Never>()
    public var updates: AnyPublisher<UUID, Never> { changes.eraseToAnyPublisher() }

    public convenience init(cacheDirectory: URL? = nil) {
        self.init(cacheDirectory: cacheDirectory,
                  loadingQueue: DispatchQueue(label: "com.aethernative.aetherscreens.thumbnail-loading", qos: .utility))
    }

    init(cacheDirectory: URL?, loadingQueue: DispatchQueue) {
        self.loadingQueue = loadingQueue
        let baseDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.cacheDirectory = cacheDirectory ?? baseDir
            .appendingPathComponent("AetherScreens", isDirectory: true)
            .appendingPathComponent("DesktopThumbnails", isDirectory: true)

        // TailScreens builds kept thumbnails directly under Caches; carry them over once.
        let legacyDirectory = baseDir.appendingPathComponent("DesktopThumbnails", isDirectory: true)
        if cacheDirectory == nil, !fileManager.fileExists(atPath: self.cacheDirectory.path),
           fileManager.fileExists(atPath: legacyDirectory.path) {
            try? fileManager.createDirectory(at: self.cacheDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fileManager.moveItem(at: legacyDirectory, to: self.cacheDirectory)
        }

        try? fileManager.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
        memoryCache.countLimit = 64
        memoryCache.totalCostLimit = 16 * 1024 * 1024
    }

    /// Memory-only lookup is safe during SwiftUI body evaluation.
    public func cachedThumbnail(for deviceId: UUID) -> CGImage? {
        memoryCache.object(forKey: deviceId.uuidString as NSString)
    }

    /// Disk I/O and immediate image decoding happen off the caller's actor.
    public func loadThumbnail(for deviceId: UUID) async -> CGImage? {
        guard !Task.isCancelled else { return nil }
        if let cached = cachedThumbnail(for: deviceId) { return cached }
        let cancellation = LoadCancellation()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                loadingQueue.async { [self] in
                    guard !cancellation.isCancelled else { continuation.resume(returning: nil); return }
                    let image = getThumbnail(for: deviceId)
                    continuation.resume(returning: cancellation.isCancelled ? nil : image)
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    /// Retrieve the cached thumbnail for a device ID
    public func getThumbnail(for deviceId: UUID) -> CGImage? {
        let key = deviceId.uuidString as NSString

        lock.lock()
        guard !removedIDs.contains(deviceId) else { lock.unlock(); return nil }
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

        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 480,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true
           ] as CFDictionary) {
            lock.lock()
            guard !removedIDs.contains(deviceId) else { lock.unlock(); return nil }
            // A newer live snapshot can arrive while disk decoding is in progress.
            if let current = memoryCache.object(forKey: key) {
                lock.unlock()
                return current
            }
            memoryCache.setObject(cg, forKey: key, cost: cg.bytesPerRow * cg.height)
            lock.unlock()
            return cg
        }

        return nil
    }

    /// Save a new desktop thumbnail for a device ID
    public func saveThumbnail(_ image: CGImage, for deviceId: UUID) {
        let key = deviceId.uuidString as NSString
        let preview = scaledPreview(image)
        // Encoding is CPU work on the snapshot worker, not a critical section
        // that a library deletion must wait through on the main actor.
        #if canImport(UIKit)
        let uiImage = UIImage(cgImage: preview)
        let encoded = uiImage.jpegData(compressionQuality: 0.75)
        #elseif canImport(AppKit)
        let rep = NSBitmapImageRep(cgImage: preview)
        let encoded = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.75])
        #else
        let encoded: Data? = nil
        #endif

        lock.lock()
        guard !removedIDs.contains(deviceId) else { lock.unlock(); return }
        memoryCache.setObject(preview, forKey: key, cost: preview.bytesPerRow * preview.height)
        let fileURL = cacheDirectory.appendingPathComponent("\(deviceId.uuidString).jpg")
        // Keep persistence ordered against removal; encoding above cannot
        // resurrect a device deleted while it was in progress.
        try? encoded?.write(to: fileURL, options: .atomic)
        lock.unlock()
        changes.send(deviceId)
    }

    /// A removed computer must not regain a preview from an in-flight session snapshot.
    public func removeThumbnail(for deviceId: UUID) {
        lock.lock()
        removedIDs.insert(deviceId)
        memoryCache.removeObject(forKey: deviceId.uuidString as NSString)
        for suffix in ["jpg", "png"] {
            try? fileManager.removeItem(at: cacheDirectory.appendingPathComponent("\(deviceId.uuidString).\(suffix)"))
        }
        lock.unlock()
        changes.send(deviceId)
    }

    private func scaledPreview(_ image: CGImage) -> CGImage {
        let maximumDimension = 480
        let longest = max(image.width, image.height)
        guard longest > maximumDimension else { return image }
        let scale = Double(maximumDimension) / Double(longest)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
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
