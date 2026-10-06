import Foundation
import CoreGraphics
import Darwin

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
    private let temporaryDirectoryLease: TemporaryThumbnailCacheDirectory?
    private let lock = NSLock()

    public init() {
        self.temporaryDirectoryLease = nil
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

    /// An injected cache never searches for or migrates production thumbnails.
    /// An externally supplied directory remains owned by its caller.
    init(cacheDirectory: URL, temporaryDirectoryLease: TemporaryThumbnailCacheDirectory? = nil) {
        self.cacheDirectory = cacheDirectory
        self.temporaryDirectoryLease = temporaryDirectoryLease
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    static func makeTemporary(parentDirectory: URL = FileManager.default.temporaryDirectory) throws -> ThumbnailStore {
        let lease = try TemporaryThumbnailCacheDirectory(parentDirectory: parentDirectory)
        return ThumbnailStore(cacheDirectory: lease.directory, temporaryDirectoryLease: lease)
    }

    var directoryURL: URL { cacheDirectory }

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

/// Only a directory created by this lease is eligible for cleanup. Directory
/// descriptors, inode verification and unlinkat prevent following a replacement
/// symlink or recursively traversing any directory placed inside the cache.
final class TemporaryThumbnailCacheDirectory: @unchecked Sendable {
    let directory: URL
    private let name: String
    private let parentDescriptor: Int32
    private let directoryDescriptor: Int32
    private let device: dev_t
    private let inode: ino_t

    init(parentDirectory: URL) throws {
        let parent = parentDirectory.resolvingSymlinksInPath().standardizedFileURL
        let name = "aetherscreens-test-thumbnails-" + UUID().uuidString
        let parentFD = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parentFD >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard mkdirat(parentFD, name, mode_t(S_IRWXU)) == 0 else {
            let failure = errno; close(parentFD)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(failure))
        }
        let directoryFD = openat(parentFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directoryFD >= 0 else {
            let failure = errno; _ = unlinkat(parentFD, name, AT_REMOVEDIR); close(parentFD)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(failure))
        }
        var info = stat()
        guard fstat(directoryFD, &info) == 0 else {
            let failure = errno; close(directoryFD); _ = unlinkat(parentFD, name, AT_REMOVEDIR); close(parentFD)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(failure))
        }
        self.directory = parent.appendingPathComponent(name, isDirectory: true)
        self.name = name
        self.parentDescriptor = parentFD
        self.directoryDescriptor = directoryFD
        self.device = info.st_dev
        self.inode = info.st_ino
    }

    deinit {
        defer { close(directoryDescriptor); close(parentDescriptor) }
        var current = stat()
        guard fstatat(parentDescriptor, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
              current.st_dev == device, current.st_ino == inode,
              current.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { return }
        let scanFD = dup(directoryDescriptor)
        guard scanFD >= 0 else { return }
        guard let entries = fdopendir(scanFD) else { close(scanFD); return }
        while let entry = readdir(entries) {
            let child = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { String(cString: $0) }
            }
            guard child != ".", child != ".." else { continue }
            // A symlink itself can be removed; a child directory is preserved
            // because it is outside the flat thumbnail cache's ownership.
            _ = unlinkat(directoryDescriptor, child, 0)
        }
        closedir(entries)
        // Recheck the entry before unlinking only this owned empty directory.
        guard fstatat(parentDescriptor, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
              current.st_dev == device, current.st_ino == inode else { return }
        _ = unlinkat(parentDescriptor, name, AT_REMOVEDIR)
    }
}
