#if os(macOS)
import Foundation
import Darwin
import AetherScreensCatalog

/// Read-only native catalog collection with native ordinary-file/directory kinds.
/// Collection neither starts a transfer nor snapshots mutable files.
enum AppleFileCopySourceCollector {
    enum Failure: Error { case invalidSource, catalog(Int32), attributes, exceedsLimit }

    static func collect(url: URL, level: UInt16) throws -> AppleFileCopySendSession.Source {
        guard url.isFileURL else { throw Failure.invalidSource }
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            path.map { open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) } ?? -1
        }
        guard descriptor >= 0 else { throw Failure.invalidSource }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG || info.st_mode & S_IFMT == S_IFDIR else { throw Failure.invalidSource }
        var header = [UInt8](repeating: 0, count: 104)
        let status = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -50 }
            return ae_collect_catalog(path, level, &header)
        }
        guard status == 0 else { throw Failure.catalog(status) }
        let metadata = try AppleFileCopyCatalogMetadata.decode(Data(header))
        var observed = stat()
        let sameSource = url.withUnsafeFileSystemRepresentation { path in
            path.map { lstat($0, &observed) == 0 } ?? false
        }
        guard sameSource, observed.st_dev == info.st_dev, observed.st_ino == info.st_ino,
              (metadata.nodeFlags & 0x10 != 0) == (info.st_mode & S_IFMT == S_IFDIR) else { throw Failure.invalidSource }

        let directory = metadata.nodeFlags & 0x10 != 0
        let entries = try AppleFileCopySourceAttributes.collect(descriptor: descriptor)
        let extensions = entries.isEmpty ? Data() : try AppleFileCopyAttributeBlock.encode(entries: entries)
        let name = url.lastPathComponent.replacingOccurrences(of: ":", with: "/")
        let initial = AppleFileCopyItem(catalogHeader: Data(header), level: level, wireName: name,
            symbolicLinkTarget: nil, extensions: extensions)
        // Normalize the derived length fields to the same header sent on wire.
        guard let item = try AppleFileCopyItem.decode(initial.message(sessionID: 0), expectedSessionID: 0) else {
            throw Failure.invalidSource
        }
        return .init(item: item, dataURL: directory ? nil : url,
            resourceURL: !directory && item.resourceForkByteCount > 0 ? url.appendingPathComponent("..namedfork/rsrc") : nil)
    }

}
#endif
