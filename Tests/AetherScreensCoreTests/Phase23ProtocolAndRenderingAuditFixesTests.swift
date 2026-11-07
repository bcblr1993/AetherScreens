import XCTest
@testable import AetherScreensCore
@testable import RDPKit

final class Phase23ProtocolAndRenderingAuditFixesTests: XCTestCase {

    func testRDPAudioFormatIsPCM16BitHandlesExtremeChannelCountsWithoutOverflowAndBoundsRates() throws {
        // Previously `channelCount * 2` overflowed UInt16 when channelCount >= 32768!
        let overflowFormat = try RDPAudioFormat(
            formatTag: RDPAudioFormatTag.pcm,
            channelCount: 40_000,
            samplesPerSecond: 48_000,
            averageBytesPerSecond: 192_000,
            blockAlign: 14_464, // 40000 * 2 mod 65536
            bitsPerSample: 16
        )
        XCTAssertFalse(overflowFormat.isPCM16Bit, "Extreme channelCount must not overflow UInt16 or pass validation")

        let extremeRateFormat = try RDPAudioFormat(
            formatTag: RDPAudioFormatTag.pcm,
            channelCount: 2,
            samplesPerSecond: 5_000_000,
            averageBytesPerSecond: 20_000_000,
            blockAlign: 4,
            bitsPerSample: 16
        )
        XCTAssertFalse(extremeRateFormat.isPCM16Bit, "Out-of-bounds sample rate must be rejected before AVAudioFormat creation")

        XCTAssertTrue(RDPAudioFormat.pcmStereo48k16Bit.isPCM16Bit)
    }

    func testRDPRSAPublicKeyEncryptRawLittleEndianUsesFastDivisionWithoutHangingOnSmallModulus() throws {
        // Previously remainderLittleEndian used repeated subtraction, hanging forever if plaintext >> modulus.
        let key = RDPRSAPublicKey(
            modulus: Data([0x11]), // modulus = 17
            publicExponent: 3,
            keyByteCount: 64
        )
        var largePlaintext = Data(repeating: 0xFF, count: 32)
        largePlaintext[31] = 0x7F
        let encrypted = try key.encryptRawLittleEndian(largePlaintext)
        XCTAssertEqual(encrypted.count, 64)

        // Also verify parseRSAPublicKey rejects a key whose top modulus byte is zero.
        var badBlob = Data()
        badBlob.append(contentsOf: [0x52, 0x53, 0x41, 0x31]) // "RSA1"
        badBlob.append(contentsOf: [72, 0, 0, 0]) // keyLength = 64 + 8
        badBlob.append(contentsOf: [0, 2, 0, 0]) // bitLength = 512
        badBlob.append(contentsOf: [63, 0, 0, 0]) // dataLength = 63
        badBlob.append(contentsOf: [1, 0, 1, 0]) // exponent = 65537
        // 64 modulus bytes where byte[0] = 2 and byte[63] = 0 (invalid MSB = 0) + 8 zero padding bytes
        var modulusBytes = [UInt8](repeating: 0, count: 72)
        modulusBytes[0] = 2
        badBlob.append(contentsOf: modulusBytes)

        var cert = Data()
        cert.append(contentsOf: [1, 0, 0, 0]) // version = 1
        cert.append(contentsOf: [1, 0, 0, 0]) // sigAlg = 1
        cert.append(contentsOf: [1, 0, 0, 0]) // keyAlg = 1
        cert.append(contentsOf: [6, 0]) // pubKeyBlobType = 6
        let blobLen = UInt16(badBlob.count)
        cert.append(contentsOf: [UInt8(blobLen & 0xFF), UInt8(blobLen >> 8)])
        cert.append(badBlob)
        cert.append(contentsOf: [8, 0]) // sigBlobType = 8
        cert.append(contentsOf: [8, 0]) // sigBlobLen = 8
        cert.append(contentsOf: [UInt8](repeating: 0, count: 8))

        XCTAssertThrowsError(try validateRDPServerCertificate(cert))
    }

    func testRDPSharedDirectoryDriveRefusesNonEmptyDirectoryDeletionRejectsSymlinksAndClosesAllHandles() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("AetherScreens_Phase23Drive_\(UUID().uuidString)", isDirectory: true)
        let outside = fm.temporaryDirectory.appendingPathComponent("AetherScreens_Phase23Outside_\(UUID().uuidString).txt")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: outside)
        defer {
            try? fm.removeItem(at: root)
            try? fm.removeItem(at: outside)
        }

        let drive = RDPSharedDirectoryDrive(deviceID: 1, rootDirectory: root, isReadOnly: false)

        // 1. Create a directory and a child file inside it
        let dirCreate = drive.handleCreate(completionID: 1, path: "subdir", createDisposition: .create, createDirectory: true)
        XCTAssertEqual(dirCreate.ioStatus, 0)
        let childCreate = drive.handleCreate(completionID: 2, path: "subdir/nested.txt", createDisposition: .create, createDirectory: false)
        XCTAssertEqual(childCreate.ioStatus, 0)
        _ = drive.handleClose(completionID: 3, fileID: childCreate.fileID)

        // Deleting a non-empty directory must fail with STATUS_DIRECTORY_NOT_EMPTY (0xC0000101) and keep child file intact!
        let deleteNonEmpty = drive.handleDelete(completionID: 4, fileID: dirCreate.fileID)
        XCTAssertEqual(deleteNonEmpty.ioStatus, 0xC000_0101)
        XCTAssertTrue(fm.fileExists(atPath: root.appendingPathComponent("subdir/nested.txt").path))

        // 2. Dangling symlink inside root pointing outside root must be rejected
        let danglingLink = root.appendingPathComponent("escape_link.txt")
        let nonExistentOutside = fm.temporaryDirectory.appendingPathComponent("AetherScreens_Dangling_\(UUID().uuidString).txt")
        try fm.createSymbolicLink(at: danglingLink, withDestinationURL: nonExistentOutside)
        defer { try? fm.removeItem(at: nonExistentOutside) }

        let symlinkCreate = drive.handleCreate(completionID: 5, path: "escape_link.txt", createDisposition: .overwriteIf)
        XCTAssertEqual(symlinkCreate.ioStatus, 0xC000_0022, "Dangling symlink escaping root must be denied")
        XCTAssertFalse(fm.fileExists(atPath: nonExistentOutside.path))

        // 3. closeAllHandles() clears all open file descriptors
        XCTAssertGreaterThan(drive.openHandleCount, 0)
        drive.closeAllHandles()
        XCTAssertEqual(drive.openHandleCount, 0)
    }

    func testStaticVirtualChannelReassemblerResetsAfterMalformedFragmentAndMCSDisconnectHandlesSlices() throws {
        var reassembler = RDPStaticVirtualChannelReassembler()

        // First fragment claims 100 bytes total, carries 20 bytes
        let first = RDPStaticVirtualChannelPDU(
            totalLength: 100,
            flags: RDPStaticVirtualChannelFlags.first | RDPStaticVirtualChannelFlags.showProtocol,
            payload: Data(repeating: 0xAA, count: 20)
        )
        XCTAssertNil(try reassembler.append(first))

        // Malformed continuation claims mismatched totalLength = 50 -> throws error AND resets state
        let malformed = RDPStaticVirtualChannelPDU(
            totalLength: 50,
            flags: RDPStaticVirtualChannelFlags.showProtocol,
            payload: Data(repeating: 0xBB, count: 20)
        )
        XCTAssertThrowsError(try reassembler.append(malformed))

        // Subsequent valid complete PDU must succeed instead of being permanently wedged
        let valid = RDPStaticVirtualChannelPDU(
            totalLength: 4,
            flags: RDPStaticVirtualChannelFlags.completeWithShowProtocol,
            payload: Data([1, 2, 3, 4])
        )
        let result = try reassembler.append(valid)
        XCTAssertEqual(result?.payload, Data([1, 2, 3, 4]))

        // Also test MCSDisconnectProviderUltimatumPDU with non-zero startIndex Data slice
        let prefixAndDisconnect = Data([0x99, 0x88, 0x03, 0x00, 0x00, 0x09, 0x02, 0xF0, 0x80, 0x21, 0x80])
        let slice = prefixAndDisconnect[2...] // startIndex == 2
        let parsed = try MCSDisconnectProviderUltimatumPDU.parseIfPresent(fromTPKT: slice)
        XCTAssertEqual(parsed?.reason, 3)
    }

    func testRDPClientDisconnectClearsLastPublishedFilesMemory() {
        let client = RDPClient(host: "10.0.0.50", port: 3389, username: "admin", password: "pw")
        client.simulateStateForTesting(.connected)
        XCTAssertTrue(
            client.publishLocalFiles([
                RDPClipboardLocalFile(fileName: "large.bin", contents: Data(repeating: 0x42, count: 65_536))
            ])
        )
        XCTAssertEqual(client.lastPublishedFiles.count, 1)

        client.disconnect()
        XCTAssertTrue(client.lastPublishedFiles.isEmpty, "disconnect() must release in-memory published clipboard file buffers")
    }
}
