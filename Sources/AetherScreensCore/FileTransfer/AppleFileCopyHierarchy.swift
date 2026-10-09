import Foundation

/// Structural manifest planning only. Filename conversion, directory creation
/// and metadata application remain the negotiated transfer owner's responsibility.
struct AppleFileCopyHierarchy {
    enum Failure: Error { case invalidLimits, exceedsLimit, missingParent }
    struct Entry: Equatable {
        let index: Int
        /// Nil denotes the chosen destination root, not a received directory.
        let parentIndex: Int?
    }
    private let maximumDepth: Int
    private let maximumItems: Int
    private var directories: [Int] = []
    private var count = 0

    init(maximumDepth: Int = 256, maximumItems: Int) throws {
        guard maximumDepth >= 0, maximumItems > 0 else { throw Failure.invalidLimits }
        self.maximumDepth = maximumDepth
        self.maximumItems = maximumItems
    }

    mutating func append(level: UInt16, isDirectory: Bool) throws -> Entry {
        let depth = Int(level)
        guard depth <= maximumDepth, count < maximumItems else { throw Failure.exceedsLimit }
        guard depth <= directories.count else { throw Failure.missingParent }
        let entry = Entry(index: count, parentIndex: depth == 0 ? nil : directories[depth - 1])
        // Discard references from a previously visited deeper branch.
        directories.removeLast(directories.count - depth)
        if isDirectory { directories.append(count) }
        count += 1
        return entry
    }

    mutating func reset() {
        directories.removeAll()
        count = 0
    }
}
