import Foundation
import Darwin

/// Darwin source collection for platforms without Carbon. File-provider access
/// must be retained by the caller; collection does not download or snapshot data.
enum AppleFileCopyPortableSourceCollector {
    enum Failure: Error { case invalidSource, attributes }
    static func collect(url: URL, level: UInt16) throws -> AppleFileCopySendSession.Source {
        guard url.isFileURL else { throw Failure.invalidSource }
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            path.map { open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) } ?? -1
        }
        guard descriptor >= 0 else { throw Failure.invalidSource }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_size >= 0,
              info.st_mode & S_IFMT == S_IFREG || info.st_mode & S_IFMT == S_IFDIR else { throw Failure.invalidSource }
        let directory = info.st_mode & S_IFMT == S_IFDIR
        let entries = try AppleFileCopySourceAttributes.collect(descriptor: descriptor)
        var finder = entries.first { $0.name == Data("com.apple.FinderInfo".utf8) }?.value ?? Data(repeating: 0, count: 32)
        guard finder.count == 32 else { throw Failure.attributes }
        // Inverse of finderInfoAttribute: native folder framing exchanges each
        // pair of UInt16 words in the first two UInt32 fields. File bytes do not.
        if directory {
            for offset in [0, 4] {
                finder.swapAt(offset, offset + 2)
                finder.swapAt(offset + 1, offset + 3)
            }
        }
        let resourceSize = directory ? 0 : fgetxattr(descriptor, "com.apple.ResourceFork", nil, 0, 0, 0)
        guard resourceSize >= 0 || errno == ENOATTR else { throw Failure.attributes }
        func timestamp(_ value: timespec) throws -> AppleFileCopyCatalogMetadata.Timestamp {
            try .init(date: Date(timeIntervalSince1970: Double(value.tv_sec) + Double(value.tv_nsec) / 1_000_000_000))
        }
        let metadata = try AppleFileCopyCatalogMetadata(rawItemKind: directory ? 2 : 1, userAccess: 0,
            wireFinderInfo: finder, created: timestamp(info.st_birthtimespec),
            contentModified: timestamp(info.st_mtimespec), attributesModified: timestamp(info.st_ctimespec),
            accessed: timestamp(info.st_atimespec), backedUp: .init(highSeconds: 0, lowSeconds: 0, fraction: 0),
            nodeFlags: directory ? 0x10 : 0, permissionMode: UInt16(info.st_mode), textEncodingHint: 0)
        let header = try metadata.encode(dataForkBytes: directory ? 0 : UInt64(info.st_size),
            resourceForkBytes: UInt64(max(0, resourceSize)), level: level)
        var observed = stat()
        let sameSource = url.withUnsafeFileSystemRepresentation { path in
            path.map { lstat($0, &observed) == 0 } ?? false
        }
        guard sameSource, observed.st_dev == info.st_dev, observed.st_ino == info.st_ino,
              observed.st_size == info.st_size, observed.st_mode == info.st_mode,
              observed.st_mtimespec.tv_sec == info.st_mtimespec.tv_sec,
              observed.st_mtimespec.tv_nsec == info.st_mtimespec.tv_nsec else { throw Failure.invalidSource }
        let extensions = entries.isEmpty ? Data() : try AppleFileCopyAttributeBlock.encode(entries: entries)
        let initial = AppleFileCopyItem(catalogHeader: header, level: level,
            wireName: url.lastPathComponent.replacingOccurrences(of: ":", with: "/"),
            symbolicLinkTarget: nil, extensions: extensions)
        guard let item = try AppleFileCopyItem.decode(initial.message(sessionID: 0), expectedSessionID: 0) else {
            throw Failure.invalidSource
        }
        return .init(item: item, dataURL: directory ? nil : url,
            resourceURL: !directory && item.resourceForkByteCount > 0 ? url.appendingPathComponent("..namedfork/rsrc") : nil)
    }
}
