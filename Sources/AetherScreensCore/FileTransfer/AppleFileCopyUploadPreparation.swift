import Foundation

/// Read-only preparation for a selected file or complete directory tree. Run
/// outside the main actor and retain any security-scoped access until sending ends.
enum AppleFileCopyUploadPreparation {
    enum Failure: Error { case invalidLimits, exceedsLimit, cancelled, invalidTree }
    struct Prepared: Sendable {
        let sources: [AppleFileCopySendSession.Source]
        let physicalBytes: UInt64
        let logicalBytes: UInt64
        let fileCount: UInt64
        let folderCount: UInt64
        let forkCount: UInt64
    }

    static func collect(url: URL, maximumItems: Int = 1024, maximumDepth: Int = 64,
                        maximumBytes: UInt64 = 1_073_741_824,
                        isCancelled: @Sendable () -> Bool = { false }) throws -> Prepared {
        guard maximumItems > 0, maximumItems <= 1024,
              maximumDepth >= 0, maximumDepth <= Int(UInt16.max) else { throw Failure.invalidLimits }
        var sources: [AppleFileCopySendSession.Source] = []
        var physical: UInt64 = 0
        var bytes: UInt64 = 0, files: UInt64 = 0, folders: UInt64 = 0, forks: UInt64 = 0
        func append(_ entry: URL, level: Int) throws {
            guard !isCancelled() else { throw Failure.cancelled }
            guard sources.count < maximumItems, level <= maximumDepth else { throw Failure.exceedsLimit }
            #if os(macOS)
            let source = try AppleFileCopySourceCollector.collect(url: entry, level: UInt16(level))
            #else
            let source = try AppleFileCopyPortableSourceCollector.collect(url: entry, level: UInt16(level))
            #endif
            for length in [source.item.dataForkByteCount, source.item.resourceForkByteCount] {
                let next = bytes.addingReportingOverflow(length)
                guard !next.overflow, next.partialValue <= maximumBytes else { throw Failure.exceedsLimit }
                bytes = next.partialValue
                if length > 0 { forks += 1 }
            }
            switch source.item.kind {
            case .file:
                files += 1
                let count = try entry.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize
                guard let count, count >= 0 else { throw Failure.invalidTree }
                let next = physical.addingReportingOverflow(UInt64(count))
                guard !next.overflow else { throw Failure.exceedsLimit }
                physical = next.partialValue
            case .directory: folders += 1
            default: throw Failure.invalidTree
            }
            sources.append(source)
        }
        try append(url, level: 0)
        if sources[0].item.kind == .directory {
            var enumerationError: Error?
            guard let enumerator = FileManager.default.enumerator(at: url,
                includingPropertiesForKeys: nil, options: [], errorHandler: { _, error in
                    enumerationError = error
                    return false
                }) else { throw Failure.invalidTree }
            // Foundation enumerates each directory before its children. The
            // native catalog levels refer to this traversal, not absolute paths.
            while let entry = enumerator.nextObject() as? URL {
                if let enumerationError { throw enumerationError }
                try append(entry, level: enumerator.level)
            }
            if let enumerationError { throw enumerationError }
        }
        guard !isCancelled() else { throw Failure.cancelled }
        return .init(sources: sources, physicalBytes: physical, logicalBytes: bytes,
                     fileCount: files, folderCount: folders, forkCount: forks)
    }
}
