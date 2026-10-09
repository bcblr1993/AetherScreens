#if os(macOS)
import XCTest
import Darwin
@testable import AetherScreensCore

final class AppleFileCopyPermissionsTests: XCTestCase {
    private func withTree(_ body: (URL, AppleFileCopyStagingFile) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aetherscreens-permissions-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let seed = root.appendingPathComponent("seed")
        try Data().write(to: seed)
        let folderHeader = try AppleFileCopySourceCollector.collect(url: root, level: 0).item.catalogHeader
        let fileHeader = try AppleFileCopySourceCollector.collect(url: seed, level: 0).item.catalogHeader
        let receiver = try AppleFileCopyReceiveSession(sessionID: 42, parentDirectory: root,
            maximumBytes: 0, maximumItems: 3)
        func item(_ header: Data, name: String, level: UInt16, mode: UInt16) -> AppleFileCopyItem {
            var modified = header
            modified[94] = UInt8(mode >> 8); modified[95] = UInt8(truncatingIfNeeded: mode)
            return .init(catalogHeader: modified, level: level, wireName: name,
                symbolicLinkTarget: nil, extensions: Data())
        }
        for metadata in [item(folderHeader, name: "folder", level: 0, mode: 0o040000),
                         item(folderHeader, name: "nested", level: 1, mode: 0o046000),
                         item(fileHeader, name: "child", level: 2, mode: 0o106444)] {
            _ = try receiver.receive(metadata.message(sessionID: 42))
        }
        _ = try receiver.receive(.init(version: 1, command: 104, sessionID: 42, body: Data([0,0,0,0])))
        let tree = try XCTUnwrap(receiver.takePreparedTrees().first)
        receiver.cancel()
        defer { tree.cancel() }
        try body(root, tree)
    }

    private func descriptor(_ url: URL) throws -> Int32 {
        let descriptor = url.withUnsafeFileSystemRepresentation { open($0!, O_RDONLY | O_NOFOLLOW) }
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        return descriptor
    }
    private func mode(_ descriptor: Int32) -> mode_t {
        var info = stat()
        XCTAssertEqual(fstat(descriptor, &info), 0)
        return info.st_mode & 0o7777
    }

    func testPermissionsRequireCatalogThenCancellationCleansZeroAccessTree() throws {
        try withTree { _, tree in
            let rootFD = try descriptor(tree.dataForkURL)
            let nestedFD = try descriptor(tree.dataForkURL.appendingPathComponent("nested"))
            let fileFD = try descriptor(tree.dataForkURL.appendingPathComponent("nested/child"))
            defer { close(rootFD); close(nestedFD); close(fileFD) }
            XCTAssertThrowsError(try tree.restorePermissions())
            try tree.restoreCatalogMetadata()
            try tree.restorePermissions()
            XCTAssertEqual(mode(rootFD), 0o700) // Private traversal until final move.
            XCTAssertEqual(mode(nestedFD), 0)
            XCTAssertEqual(mode(fileFD), 0o444)
            XCTAssertThrowsError(try tree.restoreCatalogMetadata())
            XCTAssertThrowsError(try tree.restorePermissions())
            let privateDirectory = tree.directory
            tree.cancel()
            XCTAssertFalse(FileManager.default.fileExists(atPath: privateDirectory.path))
            XCTAssertEqual(mode(rootFD), 0o700)
            XCTAssertEqual(mode(nestedFD), 0o700)
        }
    }

    func testConflictRetryAndCommitNeverRelaxCommittedDirectoryPermissions() throws {
        try withTree { root, tree in
            let rootFD = try descriptor(tree.dataForkURL)
            let nestedFD = try descriptor(tree.dataForkURL.appendingPathComponent("nested"))
            let fileFD = try descriptor(tree.dataForkURL.appendingPathComponent("nested/child"))
            // These descriptors belong solely to the test fixture; regain
            // access for fixture cleanup after checking committed permissions.
            defer {
                _ = fchmod(rootFD, 0o700); _ = fchmod(nestedFD, 0o700)
                close(rootFD); close(nestedFD); close(fileFD)
            }
            let existing = root.appendingPathComponent("folder")
            try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: false)
            try Data([99]).write(to: existing.appendingPathComponent("keep"))
            try tree.restoreCatalogMetadata()
            try tree.restorePermissions()
            XCTAssertThrowsError(try tree.commitPreparedFile(to: root))
            XCTAssertEqual(try Data(contentsOf: existing.appendingPathComponent("keep")), Data([99]))
            XCTAssertEqual(mode(rootFD), 0o700)
            let destination = try tree.commitPreparedFile(to: root, name: FileTransferRelativePath("copied"))
            XCTAssertEqual(destination.lastPathComponent, "copied")
            tree.cancel()
            XCTAssertEqual(mode(rootFD), 0)
            XCTAssertEqual(mode(nestedFD), 0)
            XCTAssertEqual(mode(fileFD), 0o444)
            XCTAssertFalse(FileManager.default.fileExists(atPath: tree.directory.path))
        }
    }
}
#endif
