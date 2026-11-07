import XCTest
@testable import AetherScreensCore
@testable import RDPKit

final class Phase9RDPDirectoryListingTests: XCTestCase {

    func testRDPSharedDirectoryQueryInformationAndDirectoryListing() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RDPDirListTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let alphaURL = tempDir.appendingPathComponent("alpha.txt")
        let betaURL = tempDir.appendingPathComponent("beta.log")
        let subDirURL = tempDir.appendingPathComponent("subdir", isDirectory: true)
        try Data("Hello World 123".utf8).write(to: alphaURL)
        try Data("Log line".utf8).write(to: betaURL)
        try FileManager.default.createDirectory(at: subDirURL, withIntermediateDirectories: true)

        let drive = RDPSharedDirectoryDrive(deviceID: 1, rootDirectory: tempDir)

        // 1. Open root directory ("/") and query information
        let rootOpen = drive.handleCreate(completionID: 1, path: "\\")
        XCTAssertEqual(rootOpen.ioStatus, 0x0000_0000)

        let rootInfo = drive.handleQueryInformation(completionID: 2, fileID: rootOpen.fileID)
        XCTAssertEqual(rootInfo.ioStatus, 0x0000_0000)
        XCTAssertTrue(rootInfo.isDirectory)

        // 2. Open regular file and query information
        let fileOpen = drive.handleCreate(completionID: 3, path: "\\alpha.txt")
        XCTAssertEqual(fileOpen.ioStatus, 0x0000_0000)
        let fileInfo = drive.handleQueryInformation(completionID: 4, fileID: fileOpen.fileID)
        XCTAssertEqual(fileInfo.ioStatus, 0x0000_0000)
        XCTAssertFalse(fileInfo.isDirectory)
        XCTAssertEqual(fileInfo.fileSize, 15)

        // 3. Query directory entries with "*"
        let allEntries = drive.handleQueryDirectory(completionID: 5, fileID: rootOpen.fileID, pattern: "*")
        XCTAssertEqual(allEntries.ioStatus, 0x0000_0000)
        XCTAssertEqual(allEntries.entries.map(\.name), ["alpha.txt", "beta.log", "subdir"])
        XCTAssertEqual(allEntries.entries.first(where: { $0.name == "subdir" })?.isDirectory, true)
        XCTAssertEqual(allEntries.entries.first(where: { $0.name == "alpha.txt" })?.fileSize, 15)

        // 4. Query directory entries with "*.txt" wildcard filter
        let txtEntries = drive.handleQueryDirectory(completionID: 6, fileID: rootOpen.fileID, pattern: "*.txt")
        XCTAssertEqual(txtEntries.ioStatus, 0x0000_0000)
        XCTAssertEqual(txtEntries.entries.map(\.name), ["alpha.txt"])

        _ = drive.handleClose(completionID: 7, fileID: fileOpen.fileID)
        _ = drive.handleClose(completionID: 8, fileID: rootOpen.fileID)
    }

    func testRemoteDeviceSharedDirectoryPathCodableAndSyncMetadata() throws {
        let device = RemoteDevice(
            name: "Win Dev Box",
            host: "10.0.0.77",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            sharedDirectoryPath: "/Users/Shared/WinExchange"
        )
        let encoded = try JSONEncoder().encode(device)
        let decoded = try JSONDecoder().decode(RemoteDevice.self, from: encoded)
        XCTAssertEqual(decoded.sharedDirectoryPath, "/Users/Shared/WinExchange")

        let meta = ComputerSyncMetadata(device: decoded)
        XCTAssertEqual(meta.sharedDirectoryPath, "/Users/Shared/WinExchange")
    }
}
