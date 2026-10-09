import Foundation

/// Plans ordinary files and directories without creating filesystem entries.
/// Catalog metadata remains attached for validation/application at finalization.
struct AppleFileCopyManifest {
    enum Failure: Error { case invalidLimits, exceedsBudget }
    struct Entry {
        let item: AppleFileCopyItem
        let parentIndex: Int?
        let path: FileTransferRelativePath
    }
    private(set) var entries: [Entry] = []
    private var hierarchy: AppleFileCopyHierarchy
    private let maximumMetadataBytes: Int
    private var metadataBytes = 0

    init(maximumItems: Int, maximumDepth: Int = 256, maximumMetadataBytes: Int = 4 * 1_048_576) throws {
        guard maximumMetadataBytes > 0 else { throw Failure.invalidLimits }
        hierarchy = try AppleFileCopyHierarchy(maximumDepth: maximumDepth, maximumItems: maximumItems)
        self.maximumMetadataBytes = maximumMetadataBytes
    }

    @discardableResult
    mutating func append(_ item: AppleFileCopyItem) throws -> Entry {
        let name = try AppleFileCopyOrdinaryName.destinationComponent(for: item)
        var nextHierarchy = hierarchy
        let placement = try nextHierarchy.append(level: item.level, isDirectory: item.isDirectory)
        let prefix = placement.parentIndex.map { entries[$0].path.path + "/" } ?? ""
        let path = try FileTransferRelativePath(prefix + name.path)
        var remaining = maximumMetadataBytes - metadataBytes
        for cost in [item.catalogHeader.count, item.wireName.utf8.count,
                     item.extensions.count, path.path.utf8.count] {
            guard cost <= remaining else { throw Failure.exceedsBudget }
            remaining -= cost
        }
        let entry = Entry(item: item, parentIndex: placement.parentIndex, path: path)
        // Commit structural state only after all validation/budget checks pass.
        hierarchy = nextHierarchy
        metadataBytes = maximumMetadataBytes - remaining
        entries.append(entry)
        return entry
    }

    mutating func reset() {
        entries.removeAll()
        metadataBytes = 0
        hierarchy.reset()
    }
}
