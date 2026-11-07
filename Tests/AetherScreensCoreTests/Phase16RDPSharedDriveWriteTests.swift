import XCTest
@testable import AetherScreensCore
@testable import RDPKit

final class Phase16RDPSharedDriveWriteTests: XCTestCase {

    func testRDPSharedDirectoryReadOnlyRejectsWriteAndDelete() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RDPWriteTests_RO_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let existingFile = tempDir.appendingPathComponent("readme.txt")
        try Data("Initial".utf8).write(to: existingFile)

        // Default is readOnly = false or when explicitly readOnly = true:
        let roDrive = RDPSharedDirectoryDrive(deviceID: 1, rootDirectory: tempDir, isReadOnly: true)

        // Creating a new file in read-only mode fails with STATUS_MEDIA_WRITE_PROTECTED (0x800000A2) or STATUS_ACCESS_DENIED (0xC0000022)
        let createNew = roDrive.handleCreate(
            completionID: 1,
            path: "\\newfile.txt",
            createDisposition: .create
        )
        XCTAssertEqual(createNew.ioStatus, 0xC000_0022)

        // Opening existing file and attempting write/truncate/delete in read-only mode fails
        let openExisting = roDrive.handleCreate(
            completionID: 2,
            path: "\\readme.txt",
            createDisposition: .open
        )
        XCTAssertEqual(openExisting.ioStatus, 0x0000_0000)

        let writeRes = roDrive.handleWrite(
            completionID: 3,
            fileID: openExisting.fileID,
            offset: 0,
            data: Data("Modified".utf8)
        )
        XCTAssertEqual(writeRes.ioStatus, 0xC000_0022)
        XCTAssertEqual(writeRes.bytesWritten, 0)

        let deleteRes = roDrive.handleDelete(completionID: 4, fileID: openExisting.fileID)
        XCTAssertEqual(deleteRes.ioStatus, 0xC000_0022)
        XCTAssertTrue(FileManager.default.fileExists(atPath: existingFile.path))
    }

    func testRDPSharedDirectoryReadWriteCreateWriteTruncateRenameAndDelete() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RDPWriteTests_RW_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rwDrive = RDPSharedDirectoryDrive(deviceID: 1, rootDirectory: tempDir, isReadOnly: false)

        // 1. Create new file via .openIf
        let created = rwDrive.handleCreate(
            completionID: 10,
            path: "\\notes.txt",
            createDisposition: .openIf
        )
        XCTAssertEqual(created.ioStatus, 0x0000_0000)
        XCTAssertEqual(created.information, 0x02) // FILE_CREATED = 0x02

        // 2. Write payload at offset 0 and offset 5
        let write1 = rwDrive.handleWrite(
            completionID: 11,
            fileID: created.fileID,
            offset: 0,
            data: Data("HelloWorld".utf8)
        )
        XCTAssertEqual(write1.ioStatus, 0x0000_0000)
        XCTAssertEqual(write1.bytesWritten, 10)

        // 3. Truncate to 5 bytes ("Hello")
        let trunc = rwDrive.handleSetEndOfFile(completionID: 12, fileID: created.fileID, size: 5)
        XCTAssertEqual(trunc.ioStatus, 0x0000_0000)

        let readBack = rwDrive.handleRead(completionID: 13, fileID: created.fileID, length: 64, offset: 0)
        XCTAssertEqual(String(data: readBack.data, encoding: .utf8), "Hello")

        // 4. Rename "\\notes.txt" -> "\\renamed.txt"
        let renameRes = rwDrive.handleRename(
            completionID: 14,
            fileID: created.fileID,
            newPath: "\\renamed.txt",
            replaceIfExists: true
        )
        XCTAssertEqual(renameRes.ioStatus, 0x0000_0000)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("renamed.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("notes.txt").path))

        // 5. Delete file
        let delRes = rwDrive.handleDelete(completionID: 15, fileID: created.fileID)
        XCTAssertEqual(delRes.ioStatus, 0x0000_0000)
        _ = rwDrive.handleClose(completionID: 16, fileID: created.fileID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("renamed.txt").path))
    }
}
