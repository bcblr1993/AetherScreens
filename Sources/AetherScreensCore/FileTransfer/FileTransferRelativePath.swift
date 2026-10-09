import Foundation

/// A relative entry name from a transfer manifest, never an arbitrary remote URL.
/// This provides lexical containment only; the writer must separately prevent
/// symlink traversal using filesystem-relative operations at creation time.
struct FileTransferRelativePath: Equatable, Sendable {
    enum Failure: Error, Equatable { case invalidPath, exceedsLimit }
    let components: [String]
    var path: String { components.joined(separator: "/") }

    init(_ path: String) throws {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.utf8.contains(0) else {
            throw Failure.invalidPath
        }
        guard path.utf8.count <= 65536 else { throw Failure.exceedsLimit }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count <= 256 else { throw Failure.exceedsLimit }
        guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw Failure.invalidPath
        }
        components = parts
    }

    /// Appending components encodes literal percent/backslash characters rather
    /// than interpreting filenames as URL escape sequences or other OS paths.
    func lexicalDestination(in directory: URL) throws -> URL {
        guard directory.isFileURL else { throw Failure.invalidPath }
        return components.reduce(directory.standardizedFileURL) {
            $0.appendingPathComponent($1, isDirectory: false)
        }
    }
}
