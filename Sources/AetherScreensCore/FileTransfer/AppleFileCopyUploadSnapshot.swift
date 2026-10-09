import Foundation
import Darwin

/// A private stable copy of a coordinated file-provider selection. Only this
/// uniquely created temporary root is removed; the selected source is read-only.
final class AppleFileCopyUploadSnapshot: @unchecked Sendable {
    enum Failure: Error { case coordination, changedSource }
    let prepared: AppleFileCopyUploadPreparation.Prepared
    private let root: URL
    private let lock = NSLock()
    private var removed = false
    private init(root: URL, prepared: AppleFileCopyUploadPreparation.Prepared) {
        self.root = root
        self.prepared = prepared
    }

    static func prepare(url: URL, maximumItems: Int = 1024, maximumDepth: Int = 64,
                        maximumBytes: UInt64 = 1_073_741_824,
                        isCancelled: @escaping @Sendable () -> Bool = { false },
                        onCopyProgress: @escaping @Sendable (UInt64) -> Void = { _ in },
                        checkSpace: @Sendable (URL, UInt64, Int) throws -> Void = {
                            try AppleFileCopyDiskSpace.check(directory: $0, payloadBytes: $1, itemCount: $2)
                        }) throws -> AppleFileCopyUploadSnapshot {
        guard !isCancelled() else { throw AppleFileCopyUploadPreparation.Failure.cancelled }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aetherscreens-upload-snapshot-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                              attributes: [.posixPermissions: 0o700])
        var retained = false
        defer { if !retained { try? FileManager.default.removeItem(at: root) } }
        var outcome: Result<AppleFileCopyUploadPreparation.Prepared, Error>?
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
            outcome = Result {
                let original = try AppleFileCopyUploadPreparation.collect(url: readable, maximumItems: maximumItems,
                    maximumDepth: maximumDepth, maximumBytes: maximumBytes, isCancelled: isCancelled)
                guard !isCancelled() else { throw AppleFileCopyUploadPreparation.Failure.cancelled }
                var copyBytes = original.logicalBytes
                for source in original.sources {
                    let sum = copyBytes.addingReportingOverflow(UInt64(source.item.extensions.count))
                    guard !sum.overflow else { throw AppleFileCopyDiskSpace.Failure.invalidSize }
                    copyBytes = sum.partialValue
                }
                try checkSpace(root, copyBytes, original.sources.count)
                let copy = root.appendingPathComponent(readable.lastPathComponent)
                do {
                    try AppleFileCopyCancellableTreeCopy.copy(from: readable, to: copy,
                        isCancelled: isCancelled, onProgress: onCopyProgress)
                } catch AppleFileCopyCancellableTreeCopy.Failure.cancelled {
                    throw AppleFileCopyUploadPreparation.Failure.cancelled
                } catch AppleFileCopyCancellableTreeCopy.Failure.cannotCopy(let code) where code == ENOSPC {
                    throw AppleFileCopyDiskSpace.Failure.insufficientSpace
                }
                let prepared = try AppleFileCopyUploadPreparation.collect(url: copy, maximumItems: maximumItems,
                    maximumDepth: maximumDepth, maximumBytes: maximumBytes, isCancelled: isCancelled)
                // A non-cooperating writer must not turn a validated selection
                // into a differently sized or shaped successful transfer.
                guard prepared.logicalBytes == original.logicalBytes,
                      prepared.fileCount == original.fileCount,
                      prepared.folderCount == original.folderCount,
                      prepared.forkCount == original.forkCount else { throw Failure.changedSource }
                func keyed(_ tree: AppleFileCopyUploadPreparation.Prepared) throws -> [[String]: AppleFileCopySendSession.Source] {
                    var result: [[String]: AppleFileCopySendSession.Source] = [:]
                    var components: [String] = []
                    for source in tree.sources {
                        let depth = Int(source.item.level)
                        guard depth <= components.count else { throw Failure.changedSource }
                        components = Array(components.prefix(depth))
                        components.append(source.item.wireName)
                        guard result[components] == nil else { throw Failure.changedSource }
                        result[components] = source
                    }
                    return result
                }
                let originals = try keyed(original)
                let copies = try keyed(prepared)
                guard originals.keys == copies.keys else { throw Failure.changedSource }
                var components: [String] = []
                let stableSources = try original.sources.map { source in
                    components = Array(components.prefix(Int(source.item.level)))
                    components.append(source.item.wireName)
                    guard let copy = copies[components], copy.item.kind == source.item.kind,
                          copy.item.dataForkByteCount == source.item.dataForkByteCount,
                          copy.item.resourceForkByteCount == source.item.resourceForkByteCount else { throw Failure.changedSource }
                    // A copy's ctime describes staging, not the user's original
                    // file. Keep observed source catalog/attributes with copy URLs.
                    return AppleFileCopySendSession.Source(item: source.item, dataURL: copy.dataURL, resourceURL: copy.resourceURL)
                }
                guard !isCancelled() else { throw AppleFileCopyUploadPreparation.Failure.cancelled }
                return .init(sources: stableSources, physicalBytes: prepared.physicalBytes,
                    logicalBytes: original.logicalBytes, fileCount: original.fileCount,
                    folderCount: original.folderCount, forkCount: original.forkCount)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else { throw Failure.coordination }
        let prepared = try outcome.get()
        retained = true
        return .init(root: root, prepared: prepared)
    }

    private static let cleanupQueue = DispatchQueue(label: "com.aethernative.aetherscreens.upload-cleanup", qos: .utility)

    /// Retain the snapshot until cleanup has executed; dropping the UI's last
    /// reference must not move recursive filesystem removal back to deinit there.
    func removeInBackground(queue: DispatchQueue? = nil, onRemoved: @escaping @Sendable () -> Void = {}) {
        (queue ?? Self.cleanupQueue).async { [self] in
            remove()
            onRemoved()
        }
    }

    func remove() {
        lock.lock()
        guard !removed else { lock.unlock(); return }
        removed = true
        lock.unlock()
        try? FileManager.default.removeItem(at: root)
    }
    deinit { remove() }
}
