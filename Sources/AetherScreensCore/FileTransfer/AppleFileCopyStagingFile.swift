import Foundation
import Darwin
#if os(macOS)
import AetherScreensCatalog
#endif

/// Single-worker ordinary-file and empty-directory receive staging.
/// The owner retains this object until final destination/metadata commit; its
/// private files are removed on cancellation, failure or deallocation.
final class AppleFileCopyStagingFile {
    enum Failure: Error {
        case unsupportedItem, exceedsBudget, unavailable, incomplete, cannotCreateFile, cannotSetAttribute
        case invalidDestination, destinationExists, cannotCommit(Int32), cannotRestoreCatalog(Int32)
        case cannotRestorePermissions(Int32)
        case committedMetadataFailure(URL, Int32)
    }
    let item: AppleFileCopyItem
    let destinationName: FileTransferRelativePath
    let directory: URL
    let dataForkURL: URL
    let resourceForkURL: URL
    private(set) var progress: AppleFileCopyForkProgress
    private let sessionID: UInt32
    private var dataHandle: FileHandle?
    private var resourceHandle: FileHandle?
    private var writable = true
    private var ownsDirectory = false
    private var prepared = false
    private struct CatalogRecord {
        let components: [String]
        let header: Data
        let device: dev_t
        let inode: ino_t
    }
    private var catalogRecords: [CatalogRecord] = []
    private var catalogRestored = false
    private var permissionsRestored = false
    private var directoryPermissionHandles: [(descriptor: Int32, mode: mode_t, isRoot: Bool)] = []

    init(item: AppleFileCopyItem, sessionID: UInt32, parentDirectory: URL,
         maximumFileBytes: UInt64) throws {
        guard parentDirectory.isFileURL else { throw Failure.cannotCreateFile }
        guard item.catalogHeader.count == 104 else { throw Failure.unsupportedItem }
        guard item.symbolicLinkTarget == nil else { throw Failure.unsupportedItem }
        guard !item.isDirectory || (item.dataForkByteCount == 0 && item.resourceForkByteCount == 0) else {
            throw Failure.unsupportedItem
        }
        let destinationName = try AppleFileCopyOrdinaryName.destinationComponent(for: item)
        let total = item.dataForkByteCount.addingReportingOverflow(item.resourceForkByteCount)
        guard !total.overflow, total.partialValue <= maximumFileBytes else { throw Failure.exceedsBudget }
        self.item = item
        self.destinationName = destinationName
        self.sessionID = sessionID
        progress = AppleFileCopyForkProgress(dataBytes: item.dataForkByteCount,
                                             resourceBytes: item.resourceForkByteCount)
        directory = parentDirectory.appendingPathComponent("incoming-\(UUID().uuidString)", isDirectory: true)
        dataForkURL = directory.appendingPathComponent("data")
        resourceForkURL = directory.appendingPathComponent("resource")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        ownsDirectory = true
        do {
            if item.isDirectory {
                try FileManager.default.createDirectory(at: dataForkURL, withIntermediateDirectories: false,
                                                        attributes: [.posixPermissions: 0o700])
                let descriptor = dataForkURL.withUnsafeFileSystemRepresentation { path in
                    path.map { open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW) } ?? -1
                }
                guard descriptor >= 0 else { throw Failure.cannotCreateFile }
                dataHandle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            } else {
                dataHandle = try Self.create(dataForkURL)
                resourceHandle = try Self.create(resourceForkURL)
            }
            var identity = stat()
            guard let descriptor = dataHandle?.fileDescriptor, fstat(descriptor, &identity) == 0 else {
                throw Failure.cannotCreateFile
            }
            catalogRecords = [.init(components: [], header: item.catalogHeader,
                device: identity.st_dev, inode: identity.st_ino)]
        } catch {
            cancel()
            throw error
        }
    }

    private static func create(_ url: URL) throws -> FileHandle {
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            path.map { open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600)) } ?? -1
        }
        guard descriptor >= 0 else { throw Failure.cannotCreateFile }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    /// Returns false for a message belonging to another command/session.
    /// Invalid data or failed writes destroy this staging attempt.
    @discardableResult
    func append(_ message: AppleFileCopyMessage, inflater: AppleFileCopyInflater) throws -> Bool {
        guard writable else { throw Failure.unavailable }
        do {
            guard let block = try AppleFileCopyDataBlock.decode(message, expectedSessionID: sessionID,
                remainingForkBytes: progress.remainingInActiveFork) else { return false }
            let bytes = try inflater.expand(block)
            guard !bytes.isEmpty, let fork = progress.activeFork else { throw Failure.incomplete }
            let handle = fork == .data ? dataHandle : resourceHandle
            guard let handle else { throw Failure.unavailable }
            try handle.write(contentsOf: bytes)
            try progress.acknowledgeWrittenBytes(UInt64(bytes.count))
            return true
        } catch {
            cancel()
            throw error
        }
    }

    /// Durable staging is not a server completion acknowledgement or a final
    /// download: metadata and the final destination still need commit.
    func finish() throws {
        guard writable else { throw Failure.unavailable }
        guard progress.isComplete else { throw Failure.incomplete }
        do {
            if !item.isDirectory { try dataHandle?.synchronize() }
            try resourceHandle?.synchronize()
            try materializeResourceFork()
            try applyExtendedAttributes()
            if !item.isDirectory { try dataHandle?.synchronize() }
            try dataHandle?.close()
            try resourceHandle?.close()
            dataHandle = nil
            resourceHandle = nil
            writable = false
            prepared = true
        } catch {
            cancel()
            throw error
        }
    }

    /// Restore the assembled tree's dates/Finder/encoding in owned staging.
    /// Children precede parents, after all payload writes and child moves.
    /// Permissions and locked flags need separate finalization ordering.
    func restoreCatalogMetadata() throws {
        guard prepared, ownsDirectory, !permissionsRestored,
              item.catalogHeader.count == 104 else { throw Failure.unavailable }
        catalogRestored = false
        let descriptor = dataForkURL.withUnsafeFileSystemRepresentation { path in
            path.map { open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) } ?? -1
        }
        guard descriptor >= 0 else { throw Failure.invalidDestination }
        defer { close(descriptor) }
        for record in catalogRecords.sorted(by: { $0.components.count > $1.components.count }) {
            guard record.header.count == 104 else { throw Failure.unsupportedItem }
            let status = try withDescriptor(for: record, root: descriptor) { current in
                #if os(macOS)
                return record.header.withUnsafeBytes {
                    ae_restore_catalog_metadata(current, $0.bindMemory(to: UInt8.self).baseAddress!)
                }
                #else
                try AppleFileCopyPortableCatalogRestore.restore(
                    AppleFileCopyCatalogMetadata.decode(record.header), descriptor: current)
                return Int32(0)
                #endif
            }
            guard status == 0 else { throw Failure.cannotRestoreCatalog(status) }
        }
        catalogRestored = true
    }

    /// Apply restrictive child permissions last. Root traversal stays available
    /// until rename; its exact mode is applied immediately after successful move.
    /// Retained directory descriptors allow
    /// cancellation to regain traversal without following paths or symlinks.
    func restorePermissions() throws {
        guard prepared, ownsDirectory, catalogRestored, !permissionsRestored else { throw Failure.unavailable }
        let descriptor = dataForkURL.withUnsafeFileSystemRepresentation { path in
            path.map { open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) } ?? -1
        }
        guard descriptor >= 0 else { throw Failure.invalidDestination }
        defer { close(descriptor) }
        do {
            for record in catalogRecords.sorted(by: { $0.components.count > $1.components.count }) {
                let metadata = try AppleFileCopyCatalogMetadata.decode(record.header)
                try withDescriptor(for: record, root: descriptor) { current in
                    var info = stat()
                    let directory = metadata.nodeFlags & 0x10 != 0
                    guard fstat(current, &info) == 0,
                          info.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG) else { throw Failure.invalidDestination }
                    if directory {
                        let retained = dup(current)
                        guard retained >= 0 else { throw Failure.cannotRestorePermissions(errno) }
                        directoryPermissionHandles.append((retained, mode_t(metadata.restoredPermissions), record.components.isEmpty))
                    }
                    let mode = metadata.restoredPermissions
                        | (directory && record.components.isEmpty ? 0o700 : 0)
                    guard fchmod(current, mode_t(mode)) == 0 else {
                        throw Failure.cannotRestorePermissions(errno)
                    }
                }
            }
            permissionsRestored = true
        } catch {
            cancel() // Regain private directory traversal before removal.
            throw error
        }
    }

    private func withDescriptor<T>(for record: CatalogRecord, root: Int32,
                                    body: (Int32) throws -> T) throws -> T {
        var current = root
        var opened: [Int32] = []
        defer { opened.reversed().forEach { close($0) } }
        for (index, component) in record.components.enumerated() {
            let flags = O_RDONLY | O_NOFOLLOW | O_NONBLOCK
                | (index < record.components.count - 1 ? O_DIRECTORY : 0)
            let next = component.withCString { openat(current, $0, flags) }
            guard next >= 0 else { throw Failure.invalidDestination }
            opened.append(next)
            current = next
        }
        var identity = stat()
        guard fstat(current, &identity) == 0, identity.st_dev == record.device,
              identity.st_ino == record.inode else { throw Failure.invalidDestination }
        return try body(current)
    }

    /// Move a prepared child into another owned staging payload and transfer
    /// its recursive catalog records to that parent. Public commit stays separate.
    func commitPreparedChild(to parent: AppleFileCopyStagingFile) throws {
        guard parent !== self, parent.prepared, parent.ownsDirectory,
              parent.item.isDirectory, prepared, ownsDirectory,
              !parent.permissionsRestored, !permissionsRestored else { throw Failure.unavailable }
        let movedRecords = catalogRecords.map {
            CatalogRecord(components: destinationName.components + $0.components, header: $0.header,
                device: $0.device, inode: $0.inode)
        }
        _ = try commitPreparedFile(to: parent.dataForkURL)
        parent.catalogRecords.append(contentsOf: movedRecords)
        parent.catalogRestored = false
    }

    /// Copy an assembled private tree into destination-side owned staging.
    /// This handles different volumes while keeping the public name unpublished.
    func copyPreparedTree(to parentDirectory: URL, isCancelled: @escaping @Sendable () -> Bool = { false }) throws -> AppleFileCopyStagingFile {
        guard prepared, ownsDirectory, !permissionsRestored else { throw Failure.unavailable }
        guard !isCancelled() else { throw AppleFileCopyCancellableTreeCopy.Failure.cancelled }
        let sourceRoot = open(dataForkURL.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard sourceRoot >= 0 else { throw Failure.invalidDestination }
        defer { close(sourceRoot) }
        var payloadBytes: UInt64 = 0
        for record in catalogRecords {
            guard !isCancelled() else { throw AppleFileCopyCancellableTreeCopy.Failure.cancelled }
            let forks = record.header[34..<50]
            let resource = forks.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            let data = forks.suffix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            let attributes = try withDescriptor(for: record, root: sourceRoot) { descriptor in
                try AppleFileCopySourceAttributes.collect(descriptor: descriptor)
            }
            for count in [resource, data] + attributes.map({ UInt64($0.name.count + $0.value.count + 1) }) {
                let sum = payloadBytes.addingReportingOverflow(count)
                guard !sum.overflow else { throw Failure.exceedsBudget }
                payloadBytes = sum.partialValue
            }
        }
        try AppleFileCopyDiskSpace.check(directory: parentDirectory, payloadBytes: payloadBytes, itemCount: catalogRecords.count)
        let copy = try AppleFileCopyStagingFile(item: item, sessionID: sessionID,
            parentDirectory: parentDirectory, maximumFileBytes: UInt64.max)
        do {
            try copy.dataHandle?.close(); copy.dataHandle = nil
            try copy.resourceHandle?.close(); copy.resourceHandle = nil
            try FileManager.default.removeItem(at: copy.dataForkURL)
            try AppleFileCopyCancellableTreeCopy.copy(from: dataForkURL, to: copy.dataForkURL, isCancelled: isCancelled)
            let root = open(copy.dataForkURL.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
            guard root >= 0 else { throw Failure.invalidDestination }
            defer { close(root) }
            copy.catalogRecords = try catalogRecords.map { record in
                var current = root
                var opened: [Int32] = []
                defer { opened.reversed().forEach { close($0) } }
                for (index, component) in record.components.enumerated() {
                    let flags = O_RDONLY | O_NOFOLLOW | O_NONBLOCK
                        | (index < record.components.count - 1 ? O_DIRECTORY : 0)
                    let next = component.withCString { openat(current, $0, flags) }
                    guard next >= 0 else { throw Failure.invalidDestination }
                    opened.append(next); current = next
                }
                let metadata = try AppleFileCopyCatalogMetadata.decode(record.header)
                var identity = stat()
                let directory = metadata.nodeFlags & 0x10 != 0
                guard fstat(current, &identity) == 0,
                      identity.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG) else { throw Failure.invalidDestination }
                if !directory {
                    func count(_ range: Range<Int>) -> UInt64 {
                        record.header[range].reduce(0) { ($0 << 8) | UInt64($1) }
                    }
                    guard identity.st_size >= 0, UInt64(identity.st_size) == count(42..<50) else { throw Failure.incomplete }
                    let resource = fgetxattr(current, "com.apple.ResourceFork", nil, 0, 0, 0)
                    guard resource >= 0 || errno == ENOATTR else { throw Failure.cannotSetAttribute }
                    guard UInt64(max(resource, 0)) == count(34..<42) else { throw Failure.incomplete }
                }
                return CatalogRecord(components: record.components, header: record.header,
                    device: identity.st_dev, inode: identity.st_ino)
            }
            copy.progress = progress
            copy.writable = false
            copy.prepared = true
            return copy
        } catch {
            copy.cancel()
            throw error
        }
    }

    /// Call only after the coordinator has confirmed session completion and any
    /// remaining catalog metadata. The existing destination is never replaced.
    func commitPreparedFile(to targetDirectory: URL) throws -> URL {
        try commitPreparedFile(to: targetDirectory, name: destinationName)
    }

    func commitPreparedFile(to targetDirectory: URL, name: FileTransferRelativePath) throws -> URL {
        guard prepared, ownsDirectory else { throw Failure.unavailable }
        guard targetDirectory.isFileURL, name.components.count == 1 else { throw Failure.invalidDestination }
        let destination = try name.lexicalDestination(in: targetDirectory)
        func openDirectory(_ url: URL) -> Int32 {
            url.withUnsafeFileSystemRepresentation { path in
                path.map { open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW) } ?? -1
            }
        }
        let source = openDirectory(directory)
        guard source >= 0 else { throw Failure.invalidDestination }
        defer { close(source) }
        let target = openDirectory(targetDirectory)
        guard target >= 0 else { throw Failure.invalidDestination }
        defer { close(target) }
        let status = name.path.withCString { filename in
            renameatx_np(source, "data", target, filename, UInt32(RENAME_EXCL))
        }
        guard status == 0 else {
            let error = errno
            if error == EEXIST { throw Failure.destinationExists }
            throw Failure.cannotCommit(error)
        }
        var metadataError: Int32?
        for handle in directoryPermissionHandles where handle.isRoot {
            if fchmod(handle.descriptor, handle.mode) != 0 { metadataError = errno }
        }
        prepared = false
        cancel() // Only the private resource sidecar/directory remain here.
        if let metadataError { throw Failure.committedMetadataFailure(destination, metadataError) }
        return destination
    }

    private func applyExtendedAttributes() throws {
        guard !item.extensions.isEmpty else { return }
        guard let block = try AppleFileCopyAttributeBlock.decode(item.extensions),
              block.trailingBytes.isEmpty, let entries = try block.entries(),
              let descriptor = dataHandle?.fileDescriptor else { throw Failure.unsupportedItem }
        let representedBytes = entries.reduce(8 + entries.count * 8) {
            $0 + $1.name.count + 1 + $1.value.count
        }
        guard representedBytes == block.payload.count else { throw Failure.unsupportedItem }
        for entry in entries {
            // Resource bytes have a separate authoritative stream. Do not let
            // a duplicate attribute silently replace that materialized fork.
            guard !entry.name.isEmpty, entry.name != Data("com.apple.ResourceFork".utf8) else {
                throw Failure.unsupportedItem
            }
            let name = entry.name.map { CChar(bitPattern: $0) } + [0]
            let status = name.withUnsafeBufferPointer { namePointer in
                entry.value.withUnsafeBytes { value in
                    fsetxattr(descriptor, namePointer.baseAddress!, value.baseAddress,
                              value.count, 0, 0)
                }
            }
            guard status == 0 else { throw Failure.cannotSetAttribute }
        }
    }

    /// Stream into the owned file's named resource fork without buffering the
    /// complete resource payload in memory. Never uses a remote path component.
    private func materializeResourceFork() throws {
        guard item.resourceForkByteCount > 0 else { return }
        let forkURL = dataForkURL.appendingPathComponent("..namedfork/rsrc")
        let descriptor = forkURL.withUnsafeFileSystemRepresentation { path in
            path.map { open($0, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, mode_t(0o600)) } ?? -1
        }
        guard descriptor >= 0 else { throw Failure.cannotCreateFile }
        let destination = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        let source = try FileHandle(forReadingFrom: resourceForkURL)
        defer { try? source.close(); try? destination.close() }
        var remaining = item.resourceForkByteCount
        while remaining > 0 {
            let count = Int(min(remaining, 65_536))
            guard let bytes = try source.read(upToCount: count), !bytes.isEmpty else {
                throw Failure.incomplete
            }
            try destination.write(contentsOf: bytes)
            remaining -= UInt64(bytes.count)
        }
        guard (try source.read(upToCount: 1) ?? Data()).isEmpty else { throw Failure.incomplete }
        try destination.synchronize()
    }

    func cancel() {
        // Successful commit sets prepared=false before cancelling its sidecar.
        // Never relax the permissions of the payload that moved to the user.
        for handle in directoryPermissionHandles {
            if prepared { _ = fchmod(handle.descriptor, mode_t(0o700)) }
            close(handle.descriptor)
        }
        directoryPermissionHandles.removeAll()
        catalogRestored = false
        permissionsRestored = false
        writable = false
        prepared = false
        try? dataHandle?.close()
        try? resourceHandle?.close()
        dataHandle = nil
        resourceHandle = nil
        catalogRecords.removeAll()
        if ownsDirectory {
            do {
                try FileManager.default.removeItem(at: directory)
                ownsDirectory = false
            } catch {
                if !FileManager.default.fileExists(atPath: directory.path) { ownsDirectory = false }
            }
        }
    }

    deinit { cancel() }
}
