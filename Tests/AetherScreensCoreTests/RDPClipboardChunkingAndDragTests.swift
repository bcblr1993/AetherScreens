import XCTest
import CoreImage
import CoreVideo
import RDPKit
@testable import RDPKit
@testable import AetherScreensCore

final class RDPClipboardChunkingAndDragTests: XCTestCase {

    func testStaticVirtualChannelChunkingExceedingSinglePayload() throws {
        let payloadSize = 65536 // 64 KB (standard Windows Explorer read buffer)
        let largeData = Data((0..<payloadSize).map { UInt8($0 & 0xFF) })

        XCTAssertFalse(RDPStaticVirtualChannelPDU.canEncodeSinglePayload(largeData))

        let chunks = RDPStaticVirtualChannelPDU.chunkPayload(largeData)
        XCTAssertGreaterThan(chunks.count, 1)

        let totalLength = UInt32(largeData.count)
        for (index, chunk) in chunks.enumerated() {
            XCTAssertEqual(chunk.totalLength, totalLength)
            XCTAssertLessThanOrEqual(chunk.payload.count, RDPStaticVirtualChannelPDU.maximumPayloadByteCount)
            XCTAssertNotEqual(chunk.flags & RDPStaticVirtualChannelFlags.showProtocol, 0)

            if index == 0 {
                XCTAssertNotEqual(chunk.flags & RDPStaticVirtualChannelFlags.first, 0)
                XCTAssertEqual(chunk.flags & RDPStaticVirtualChannelFlags.last, 0)
            } else if index == chunks.count - 1 {
                XCTAssertEqual(chunk.flags & RDPStaticVirtualChannelFlags.first, 0)
                XCTAssertNotEqual(chunk.flags & RDPStaticVirtualChannelFlags.last, 0)
            } else {
                XCTAssertEqual(chunk.flags & RDPStaticVirtualChannelFlags.first, 0)
                XCTAssertEqual(chunk.flags & RDPStaticVirtualChannelFlags.last, 0)
            }
        }

        // Reassembly test
        var reassembler = RDPStaticVirtualChannelReassembler()
        var assembledPDU: RDPStaticVirtualChannelPDU?
        for (index, chunk) in chunks.enumerated() {
            let result = try reassembler.append(chunk)
            if index < chunks.count - 1 {
                XCTAssertNil(result, "Intermediate chunk should not finalize assembly")
            } else {
                assembledPDU = result
            }
        }

        XCTAssertNotNil(assembledPDU)
        XCTAssertEqual(assembledPDU?.payload.count, payloadSize)
        XCTAssertEqual(assembledPDU?.payload, largeData)
    }

    func testStaticVirtualChannelZeroBytePayload() throws {
        let empty = Data()
        let chunks = RDPStaticVirtualChannelPDU.chunkPayload(empty)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].totalLength, 0)
        XCTAssertEqual(chunks[0].payload.count, 0)
        XCTAssertTrue(chunks[0].isComplete)

        var reassembler = RDPStaticVirtualChannelReassembler()
        let assembled = try reassembler.append(chunks[0])
        XCTAssertEqual(assembled?.payload, empty)
    }

    func testFileGroupDescriptorWExceedingSinglePayloadChunking() throws {
        // Create 10 files to make FileGroupDescriptorW well over 1592 bytes (10 * 592 + 4 = 5924 bytes)
        var descriptors: [RDPClipboardFileDescriptorW] = []
        for i in 0..<10 {
            descriptors.append(RDPClipboardFileDescriptorW(
                flags: RDPClipboardFileDescriptorFlags.attributes | RDPClipboardFileDescriptorFlags.fileSize | RDPClipboardFileDescriptorFlags.unicode,
                fileAttributes: RDPClipboardFileAttributes.archive,
                fileSize: UInt64(1000 + i),
                fileName: "file_\(i).dat"
            ))
        }

        let groupDescriptor = RDPClipboardFileGroupDescriptorW(descriptors: descriptors)
        let responsePDU = RDPClipboardFormatDataResponsePDU.fileGroupDescriptorW(groupDescriptor)
        let encodedPayload = responsePDU.encoded()

        XCTAssertGreaterThan(encodedPayload.count, RDPStaticVirtualChannelPDU.maximumPayloadByteCount)
        XCTAssertFalse(RDPStaticVirtualChannelPDU.canEncodeSinglePayload(encodedPayload))

        let chunks = RDPStaticVirtualChannelPDU.chunkPayload(encodedPayload)
        XCTAssertGreaterThan(chunks.count, 1)

        var reassembler = RDPStaticVirtualChannelReassembler()
        var assembled: RDPStaticVirtualChannelPDU?
        for chunk in chunks {
            assembled = try reassembler.append(chunk)
        }

        let assembledData = try XCTUnwrap(assembled?.payload)
        let parsedPDU = try RDPClipboardPDU.parse(from: assembledData)
        let parsedResponse = try XCTUnwrap(RDPClipboardFormatDataResponsePDU.parseIfPresent(from: parsedPDU))
        let parsedGroup = try parsedResponse.decodedFileGroupDescriptorW()
        XCTAssertEqual(parsedGroup.descriptors.count, 10)
        XCTAssertEqual(parsedGroup.descriptors[0].fileName, "file_0.dat")
        XCTAssertEqual(parsedGroup.descriptors[9].fileName, "file_9.dat")
    }

    @MainActor
    func testSessionViewModelDownloadedFilesPillAndReveal() async throws {
        let device = RemoteDevice(
            name: "Win11 Workstation",
            host: "192.0.2.50",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "rdpuser"
        )
        let session = SessionViewModel(device: device, password: "123", isTemporary: true)
        defer { session.endSession() }

        guard let rdpClient = session.rdpClient else {
            XCTFail("RDP client should be present")
            return
        }

        rdpClient.simulateStateForTesting(.connected)
        let drain = expectation(description: "Connected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { drain.fulfill() }
        await fulfillment(of: [drain], timeout: 1)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sample1 = tempDir.appendingPathComponent("image.png")
        let sample2 = tempDir.appendingPathComponent("document.docx")
        try "png data".write(to: sample1, atomically: true, encoding: .utf8)
        try "docx data".write(to: sample2, atomically: true, encoding: .utf8)

        XCTAssertTrue(session.downloadedRemoteFiles.isEmpty)

        // Simulate incoming clipboard files from Windows
        rdpClient.simulateClipboardFilesForTesting([sample1, sample2])

        let receiveExp = expectation(description: "Receive clipboard files")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { receiveExp.fulfill() }
        await fulfillment(of: [receiveExp], timeout: 1)

        XCTAssertEqual(session.downloadedRemoteFiles.count, 2)
        XCTAssertEqual(session.downloadedRemoteFiles[0].lastPathComponent, "image.png")
        XCTAssertEqual(session.downloadedRemoteFiles[1].lastPathComponent, "document.docx")

        // Reveal files in Finder safely without crash
        session.revealDownloadedFiles()

        // Clear files
        session.downloadedRemoteFiles = []
        XCTAssertTrue(session.downloadedRemoteFiles.isEmpty)
    }

    @MainActor
    func testTransferDroppedFilesToRDPWithFormatListAck() async throws {
        let device = RemoteDevice(
            name: "Win11 Workstation",
            host: "192.0.2.50",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "rdpuser"
        )
        let session = SessionViewModel(device: device, password: "123", isTemporary: true)
        defer { session.endSession() }

        guard let rdpClient = session.rdpClient else {
            XCTFail("RDP client should be present")
            return
        }

        rdpClient.simulateStateForTesting(.connected)
        let drain = expectation(description: "Connected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { drain.fulfill() }
        await fulfillment(of: [drain], timeout: 1)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dropFile = tempDir.appendingPathComponent("transfer_test.jpg")
        try "jpg data".write(to: dropFile, atomically: true, encoding: .utf8)

        session.transferDroppedFilesToRDP(
            urls: [dropFile],
            at: CGPoint(x: 300, y: 400),
            in: CGSize(width: 1024, height: 768)
        )

        XCTAssertEqual(rdpClient.lastPublishedFiles.count, 1)
        XCTAssertEqual(rdpClient.lastPublishedFiles.first?.descriptor.fileName, "transfer_test.jpg")
        XCTAssertNotNil(session.fileUploadNotice)
        XCTAssertTrue(session.fileUploadNotice?.contains("transfer_test.jpg") == true)
        XCTAssertNotNil(rdpClient.lastPointerPosition)
        XCTAssertGreaterThan(rdpClient.lastPointerPosition?.0 ?? 0, 0)
        XCTAssertGreaterThan(rdpClient.lastPointerPosition?.1 ?? 0, 0)

        // Verify that syncLocalClipboardIfNeeded preserves the published files and does not overwrite with text
        session.syncLocalClipboardIfNeeded()
        XCTAssertFalse(rdpClient.lastPublishedFiles.isEmpty, "syncLocalClipboardIfNeeded must not clear published files")
    }

    @MainActor
    func testRDPFileTransferProgressAndCompletion() async throws {
        let device = RemoteDevice(
            name: "Win11 Workstation",
            host: "192.0.2.50",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "rdpuser"
        )
        let session = SessionViewModel(device: device, password: "123", isTemporary: true)
        defer { session.endSession() }

        guard let rdpClient = session.rdpClient else {
            XCTFail("RDP client should be present")
            return
        }

        rdpClient.simulateStateForTesting(.connected)
        let drain = expectation(description: "Connected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { drain.fulfill() }
        await fulfillment(of: [drain], timeout: 1)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sample = tempDir.appendingPathComponent("document.pdf")
        let data = Data(repeating: 0x41, count: 10000)
        try data.write(to: sample)

        session.transferDroppedFilesToRDP(urls: [sample])

        // Verify that an upload job was registered in session.fileTransfers
        let uploadJobs = session.fileTransfers.jobs.filter { $0.direction == .upload }
        XCTAssertFalse(uploadJobs.isEmpty)
        XCTAssertEqual(uploadJobs.first?.filename, "document.pdf")
        XCTAssertEqual(uploadJobs.first?.totalBytes, 10000)

        // Simulate upload progress
        rdpClient.onFileUploadProgress?("document.pdf", 5000, 10000)
        let progressDrain = expectation(description: "Progress")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { progressDrain.fulfill() }
        await fulfillment(of: [progressDrain], timeout: 1)

        let updatedJob = session.fileTransfers.jobs.first(where: { $0.filename == "document.pdf" })
        XCTAssertEqual(updatedJob?.transferredBytes, 5000)

        // Complete upload
        rdpClient.onFileUploadProgress?("document.pdf", 10000, 10000)
        let completeDrain = expectation(description: "Complete")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { completeDrain.fulfill() }
        await fulfillment(of: [completeDrain], timeout: 1)

        let completedJob = session.fileTransfers.jobs.first(where: { $0.filename == "document.pdf" })
        XCTAssertEqual(completedJob?.state, .completed)
    }

    @MainActor
    func testTextClipboardSyncWorksAfterPublishingFiles() async throws {
        var currentText: String?
        var currentFiles: [URL]?
        var changeCount = 1

        let device = RemoteDevice(
            name: "Win11 Workstation",
            host: "192.0.2.50",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "rdpuser"
        )
        let session = SessionViewModel(
            device: device,
            password: "123",
            isTemporary: true,
            clipboardWriter: { currentText = $0; currentFiles = nil; changeCount += 1 },
            clipboardReader: { currentText },
            clipboardFilesWriter: { currentFiles = $0; currentText = $0.first?.lastPathComponent; changeCount += 1 },
            clipboardFilesReader: { currentFiles },
            clipboardChangeCount: { changeCount },
            clipboardIsConcealed: { false }
        )
        defer { session.endSession() }

        guard let rdpClient = session.rdpClient else {
            XCTFail("RDP client should be present")
            return
        }

        rdpClient.simulateStateForTesting(.connected)
        let drain = expectation(description: "Connected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { drain.fulfill() }
        await fulfillment(of: [drain], timeout: 1)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("report.txt")
        try "sample report".write(to: fileURL, atomically: true, encoding: .utf8)

        XCTAssertTrue(session.publishFilesToRDP(urls: [fileURL], notify: true))
        XCTAssertEqual(rdpClient.lastPublishedFiles.count, 1)

        // Subsequent poll without pasteboard change must not clear published files
        session.syncLocalClipboardIfNeeded()
        XCTAssertEqual(rdpClient.lastPublishedFiles.count, 1)

        // Now user copies plain text locally after having transferred a file
        currentFiles = nil
        currentText = "Copied text after file transfer"
        changeCount += 1

        session.syncLocalClipboardIfNeeded()
        XCTAssertTrue(rdpClient.lastPublishedFiles.isEmpty, "Copying plain text should replace published files and sync text")
    }

    @MainActor
    func testCancellingRDPFileDownloadDoesNotDisconnectSession() async throws {
        let device = RemoteDevice(
            name: "Win11 Workstation",
            host: "192.0.2.50",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "rdpuser"
        )
        let session = SessionViewModel(device: device, password: "123", isTemporary: true)
        defer { session.endSession() }

        guard let rdpClient = session.rdpClient else {
            XCTFail("RDP client should be present")
            return
        }

        rdpClient.simulateStateForTesting(.connected)
        let drain = expectation(description: "Connected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { drain.fulfill() }
        await fulfillment(of: [drain], timeout: 1)

        let desc = RDPClipboardFileDescriptorW(
            flags: RDPClipboardFileDescriptorFlags.attributes | RDPClipboardFileDescriptorFlags.fileSize | RDPClipboardFileDescriptorFlags.unicode,
            fileAttributes: RDPClipboardFileAttributes.archive,
            fileSize: 4096,
            fileName: "archive.zip"
        )
        rdpClient.onRemoteFilesAdvertised?([desc])

        let advertiseDrain = expectation(description: "Advertised")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { advertiseDrain.fulfill() }
        await fulfillment(of: [advertiseDrain], timeout: 1)

        let downloadJob = try XCTUnwrap(session.fileTransfers.jobs.first(where: { $0.filename == "archive.zip" }))
        session.fileTransfers.cancel(downloadJob.id)

        XCTAssertEqual(rdpClient.state, .connected, "Cancelling file download must not disconnect the active RDP session")
    }

    func testComputerSyncPreservesRDPMetadataAndFavorites() throws {
        let rdpDevice = RemoteDevice(
            name: "Studio Windows PC",
            host: "100.64.1.25",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "Administrator",
            isFavorite: true,
            tags: ["Work", "GPU"],
            desktopWidth: 2560,
            desktopHeight: 1440,
            remoteAudioEnabled: false,
            autoFitResolution: false
        )

        var journal = ComputerSyncJournal()
        try journal.captureLocalComputers([rdpDevice])
        let encoded = try journal.encoded()
        let restored = try ComputerSyncJournal(restoring: encoded)
        let metadata = try XCTUnwrap(restored.computers.first)

        XCTAssertEqual(metadata.remoteProtocol, .rdp)
        XCTAssertEqual(metadata.isFavorite, true)
        XCTAssertEqual(metadata.tags, ["Work", "GPU"])
        XCTAssertEqual(metadata.desktopWidth, 2560)
        XCTAssertEqual(metadata.desktopHeight, 1440)
        XCTAssertEqual(metadata.remoteAudioEnabled, false)
        XCTAssertEqual(metadata.autoFitResolution, false)
    }

    func testUpdateFromPixelBufferCopiesOnlyDirtyRegions() throws {
        let fb = Framebuffer(width: 4, height: 4)
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            4,
            4,
            kCVPixelFormatType_32BGRA,
            nil,
            &pb
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        let pixelBuffer = try XCTUnwrap(pb)

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
            for row in 0..<4 {
                let rowPtr = base.advanced(by: row * stride).assumingMemoryBound(to: UInt8.self)
                for col in 0..<4 {
                    rowPtr[col * 4] = 0x11
                    rowPtr[col * 4 + 1] = 0x22
                    rowPtr[col * 4 + 2] = 0x33
                    rowPtr[col * 4 + 3] = 0xFF
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        let ciContext = CIContext(options: [.useSoftwareRenderer: true])
        fb.updateFromPixelBuffer(
            pixelBuffer,
            dirtyRects: [(x: 1, y: 1, width: 2, height: 2)],
            fallbackContext: ciContext
        )

        // (0,0) should remain 0, while (1,1) should have [0x11, 0x22, 0x33, 0xFF]
        XCTAssertEqual(fb.pixels[0], 0)
        let insideIndex = (1 * 4 + 1) * 4
        XCTAssertEqual(Array(fb.pixels[insideIndex..<(insideIndex + 4)]), [0x11, 0x22, 0x33, 0xFF])
    }

    func testDecodeRemotePointerImage32BitAnd24Bit() throws {
        // 2x2 32-bit bottom-up pointer with explicit alpha
        var xor32 = Data(repeating: 0, count: 2 * 8)
        // Row 0 in bottom-up storage corresponds to top row y=1; Row 1 corresponds to top row y=0
        xor32[8] = 100 // B at (0,0)
        xor32[9] = 150 // G at (0,0)
        xor32[10] = 200 // R at (0,0)
        xor32[11] = 255 // A at (0,0)
        let andMask = Data(repeating: 0, count: 2 * 2)
        let image32 = RDPRemotePointerImage(
            cacheIndex: 0,
            hotSpot: RDPRemotePoint(x: 1, y: 1),
            width: 2,
            height: 2,
            xorBitsPerPixel: 32,
            xorMaskData: xor32,
            andMaskData: andMask
        )
        let cursor32 = try XCTUnwrap(RDPClient.decodeRemotePointerImage(image32))
        XCTAssertEqual(cursor32.width, 2)
        XCTAssertEqual(cursor32.height, 2)
        XCTAssertEqual(cursor32.hotspotX, 1)
        XCTAssertEqual(cursor32.hotspotY, 1)
        XCTAssertEqual(Array(cursor32.pixels.prefix(4)), [100, 150, 200, 255])
        XCTAssertNotNil(cursor32.makeCGImage())
    }

    @MainActor
    func testShowFileUploadNoticeCancelsPreviousDismissTimer() async throws {
        let device = RemoteDevice(
            name: "Win11 Workstation",
            host: "192.0.2.50",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            authMethod: .windowsCredentials,
            username: "rdpuser"
        )
        let session = SessionViewModel(device: device, password: "123", isTemporary: true)
        defer { session.endSession() }

        session.showFileUploadNotice("First notice", durationNanoseconds: 80_000_000)
        try await Task.sleep(nanoseconds: 30_000_000)
        session.showFileUploadNotice("Second notice", durationNanoseconds: 300_000_000)
        try await Task.sleep(nanoseconds: 90_000_000)

        // First timer would have fired at 80ms; verify "Second notice" was not prematurely cleared
        XCTAssertEqual(session.fileUploadNotice, "Second notice")
    }
}
