import Foundation

/// Converts legacy FSUnicode names for ordinary files/directories to a single
/// POSIX component. Symbolic-link names follow a different sender branch.
enum AppleFileCopyOrdinaryName {
    enum Failure: Error { case unsupportedSymbolicLink, invalidName }

    static func destinationComponent(for item: AppleFileCopyItem) throws -> FileTransferRelativePath {
        guard item.symbolicLinkTarget == nil else { throw Failure.unsupportedSymbolicLink }
        let name = item.wireName
        guard !name.isEmpty, name.utf16.count <= 255, !name.contains(":"),
              !name.utf8.contains(0) else { throw Failure.invalidName }
        return try FileTransferRelativePath(name.replacingOccurrences(of: "/", with: ":"))
    }
}
