import XCTest
@testable import RDPKit

final class Phase5DriveRedirectionTests: XCTestCase {

    func testDeviceListAnnounceWithFilesystemDriveEncodesValidHeader() throws {
        let drive = RDPDeviceRedirectionAnnouncedDrive(deviceID: 1, preferredDosName: "AETHER")
        let announce = RDPDeviceRedirectionDeviceListAnnounce(drives: [drive])
        let encoded = announce.encoded()

        let pdu = try RDPDeviceRedirectionPDU.parse(from: encoded)
        XCTAssertEqual(pdu.header.component, RDPDeviceRedirectionComponent.core)
        XCTAssertEqual(pdu.header.packetID, RDPDeviceRedirectionPacketID.deviceListAnnounce)

        // Payload: 4-byte deviceCount (1) + 20-byte DEVICE_ANNOUNCE header (deviceType=8, deviceID=1, preferredDosName="AETHER\0\0", deviceDataLength=0)
        XCTAssertEqual(pdu.payload.count, 24)
    }

    func testSharedDirectoryDriveHandlesCreateReadCloseAndBlocksTraversal() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RDPSharedDriveTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let helloFile = tempDir.appendingPathComponent("hello.txt")
        try Data("Hello from Mac!".utf8).write(to: helloFile)

        let drive = RDPSharedDirectoryDrive(deviceID: 1, rootDirectory: tempDir)

        // 1. Path traversal attempt ("..\\secret.txt") must fail with STATUS_ACCESS_DENIED (0xC0000022)
        let traversalCreate = drive.handleCreate(completionID: 10, path: "\\..\\secret.txt")
        XCTAssertEqual(traversalCreate.ioStatus, 0xC000_0022)

        // 2. Open valid file "\hello.txt"
        let openResp = drive.handleCreate(completionID: 11, path: "\\hello.txt")
        XCTAssertEqual(openResp.ioStatus, 0x0000_0000)
        XCTAssertGreaterThan(openResp.fileID, 0)

        // 3. Read 5 bytes at offset 6 ("from ")
        let readResp = drive.handleRead(completionID: 12, fileID: openResp.fileID, length: 5, offset: 6)
        XCTAssertEqual(readResp.ioStatus, 0x0000_0000)
        XCTAssertEqual(String(data: readResp.data, encoding: .utf8), "from ")

        // 4. Close fileID and verify subsequent read fails with STATUS_INVALID_HANDLE (0xC0000008)
        let closeResp = drive.handleClose(completionID: 13, fileID: openResp.fileID)
        XCTAssertEqual(closeResp.ioStatus, 0x0000_0000)

        let readAfterClose = drive.handleRead(completionID: 14, fileID: openResp.fileID, length: 5, offset: 0)
        XCTAssertEqual(readAfterClose.ioStatus, 0xC000_0008)
    }
}
