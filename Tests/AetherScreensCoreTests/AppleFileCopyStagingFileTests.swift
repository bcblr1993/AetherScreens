import XCTest
import Darwin
@testable import AetherScreensCore

final class AppleFileCopyStagingFileTests: XCTestCase {
    func testDirectoryStagingCommitsWithoutReplacingExistingFolder() throws {
        let root = try parent()
        defer { try? FileManager.default.removeItem(at: root) }
        let base = try item(data: 0, resource: 0, name: "目录")
        var header = base.catalogHeader
        header[91] = 0x10
        let attributeName = "com.aethernative.qa.directory"
        let attributeValue = Data([0, 255, 7, 0])
        let key = Data(attributeName.utf8) + Data([0])
        var table = Data()
        let tableByteCount = UInt32(16 + key.count + attributeValue.count)
        let tableFields: [UInt32] = [tableByteCount, 1, UInt32(key.count), UInt32(attributeValue.count)]
        for number in tableFields {
            withUnsafeBytes(of: number.bigEndian) { table.append(contentsOf: $0) }
        }
        table.append(key)
        table.append(attributeValue)
        var extensionBlock = Data([0x65, 0x78, 0x74, 0x31, 0, 0, 0, 1])
        withUnsafeBytes(of: UInt16(table.count + 10).bigEndian) { extensionBlock.append(contentsOf: $0) }
        extensionBlock.append(table)
        let folder = AppleFileCopyItem(catalogHeader: header, level: 0, wireName: base.wireName,
                                      symbolicLinkTarget: nil, extensions: extensionBlock)
        let staging = try AppleFileCopyStagingFile(item: folder, sessionID: 7,
            parentDirectory: root, maximumFileBytes: 0)
        defer { staging.cancel() }
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: staging.dataForkURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.resourceForkURL.path))
        try staging.finish()
        #if os(macOS)
        let existing = root.appendingPathComponent("existing")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: false)
        try Data([99]).write(to: existing.appendingPathComponent("keep"))
        XCTAssertThrowsError(try staging.commitPreparedFile(to: root, name: FileTransferRelativePath("existing")))
        XCTAssertEqual(try Data(contentsOf: existing.appendingPathComponent("keep")), Data([99]))
        let destination = try staging.commitPreparedFile(to: root)
        XCTAssertEqual(destination.lastPathComponent, "目录")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
        var restored = Data(count: attributeValue.count)
        let count = destination.withUnsafeFileSystemRepresentation { path in
            attributeName.withCString { name in
                restored.withUnsafeMutableBytes { buffer in
                    getxattr(path!, name, buffer.baseAddress, buffer.count, 0, 0)
                }
            }
        }
        XCTAssertEqual(count, attributeValue.count)
        XCTAssertEqual(restored, attributeValue)
        staging.cancel()
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        #endif
    }

    func testInvalidNativeNameFailsBeforeStagingAndDefaultCommitPreservesName() throws {
        let root = try parent()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try AppleFileCopyStagingFile(
            item: item(data: 0, resource: 0, name: "invalid:colon"), sessionID: 7,
            parentDirectory: root, maximumFileBytes: 0))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        let staging = try AppleFileCopyStagingFile(
            item: item(data: 0, resource: 0, name: "报告/2026%2F.txt"), sessionID: 7,
            parentDirectory: root, maximumFileBytes: 0)
        defer { staging.cancel() }
        XCTAssertEqual(staging.destinationName.components, ["报告:2026%2F.txt"])
        try staging.finish()
        #if os(macOS)
        let destination = try staging.commitPreparedFile(to: root)
        XCTAssertEqual(destination.lastPathComponent, "报告:2026%2F.txt")
        XCTAssertEqual(try Data(contentsOf: destination), Data())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["报告:2026%2F.txt"])
        #endif
    }

    private func item(data: UInt64, resource: UInt64, name: String = "../untrusted",
                      extensions: Data = Data()) throws -> AppleFileCopyItem {
        var header = Data(repeating: 0, count: 104)
        for (offset, value) in [(34, resource), (42, data)] {
            for index in 0..<8 { header[offset + index] = UInt8(truncatingIfNeeded: value >> ((7 - index) * 8)) }
        }
        let nameBytes = Data(name.utf8)
        header[100] = UInt8(nameBytes.count >> 8); header[101] = UInt8(nameBytes.count & 255)
        return try XCTUnwrap(AppleFileCopyItem.decode(
            .init(version: 1, command: 101, sessionID: 7, body: header + nameBytes + Data([0]) + extensions),
            expectedSessionID: 7))
    }

    private func raw(_ bytes: Data, session: UInt32 = 7) -> AppleFileCopyMessage {
        var body = Data()
        withUnsafeBytes(of: UInt32(bytes.count).bigEndian) { body.append(contentsOf: $0) }
        body.append(bytes)
        return .init(version: 1, command: 102, sessionID: session, body: body)
    }

    private func parent() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("file-staging-qa-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    func testDiskStagingPreservesBothForksAndNeverUsesWireNameAsPath() throws {
        let root = try parent()
        defer { try? FileManager.default.removeItem(at: root) }
        let staging = try AppleFileCopyStagingFile(item: item(data: 5, resource: 3),
            sessionID: 7, parentDirectory: root, maximumFileBytes: 8)
        let inflater = AppleFileCopyInflater()
        XCTAssertFalse(try staging.append(raw(Data([1]), session: 8), inflater: inflater))
        XCTAssertThrowsError(try staging.finish())
        try staging.append(raw(Data([1, 0])), inflater: inflater)
        try staging.append(raw(Data([255, 2, 3])), inflater: inflater)
        XCTAssertEqual(staging.progress.activeFork, .resource)
        try staging.append(raw(Data([0, 0xff, 0x80])), inflater: inflater)
        try staging.finish()
        XCTAssertEqual(try Data(contentsOf: staging.dataForkURL), Data([1, 0, 255, 2, 3]))
        XCTAssertEqual(try Data(contentsOf: staging.resourceForkURL), Data([0, 0xff, 0x80]))
        #if os(macOS)
        XCTAssertEqual(try Data(contentsOf: staging.dataForkURL.appendingPathComponent("..namedfork/rsrc")),
                       Data([0, 0xff, 0x80]))
        #endif
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staging.directory.path).sorted(), ["data", "resource"])
        XCTAssertThrowsError(try staging.append(raw(Data([1])), inflater: inflater))
        staging.cancel()
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.directory.path))
    }

    func testMalformedOverrunDestroysAttemptWithoutTouchingSibling() throws {
        let root = try parent()
        defer { try? FileManager.default.removeItem(at: root) }
        let sentinel = root.appendingPathComponent("keep")
        try Data([0xab]).write(to: sentinel)
        let staging = try AppleFileCopyStagingFile(item: item(data: 1, resource: 2),
            sessionID: 7, parentDirectory: root, maximumFileBytes: 3)
        XCTAssertThrowsError(try staging.append(raw(Data([1, 2])), inflater: AppleFileCopyInflater()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.directory.path))
        XCTAssertThrowsError(try staging.finish())
        XCTAssertEqual(try Data(contentsOf: sentinel), Data([0xab]))
    }

    func testPersistentCompressedBlocksProduceExactDiskBytes() throws {
        let root = try parent()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = Data((0..<32768).map { UInt8(truncatingIfNeeded: $0 * 37) })
        let second = Data(first.suffix(16384))
        let source = first + second
        let staging = try AppleFileCopyStagingFile(item: item(data: UInt64(source.count), resource: 0),
            sessionID: 7, parentDirectory: root, maximumFileBytes: UInt64(source.count))
        let deflater = try ZRLETestDeflater()
        let inflater = AppleFileCopyInflater()
        for bytes in [first, second] {
            let compressed = try deflater.compress(bytes)
            var body = Data([0, 1])
            for value in [UInt32(bytes.count), UInt32(compressed.count)] {
                withUnsafeBytes(of: value.bigEndian) { body.append(contentsOf: $0) }
            }
            body.append(compressed)
            try staging.append(.init(version: 1, command: 103, sessionID: 7, body: body), inflater: inflater)
        }
        try staging.finish()
        XCTAssertEqual(try Data(contentsOf: staging.dataForkURL), source)
        XCTAssertEqual(try Data(contentsOf: staging.resourceForkURL), Data())
    }

    #if os(macOS)
    func testAtomicCommitPreservesExistingFileAndSupportsRetryWithNewName() throws {
        let root = try parent()
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = root.appendingPathComponent("existing")
        try Data([0xee]).write(to: existing)
        let staging = try AppleFileCopyStagingFile(item: item(data: 2, resource: 3),
            sessionID: 7, parentDirectory: root, maximumFileBytes: 5)
        XCTAssertThrowsError(try staging.commitPreparedFile(to: root, name: FileTransferRelativePath("new")))
        let inflater = AppleFileCopyInflater()
        try staging.append(raw(Data([1, 2])), inflater: inflater)
        try staging.append(raw(Data([0, 0xff, 3])), inflater: inflater)
        try staging.finish()
        XCTAssertThrowsError(try staging.commitPreparedFile(to: root, name: FileTransferRelativePath("existing"))) { error in
            guard case AppleFileCopyStagingFile.Failure.destinationExists = error else {
                return XCTFail("Expected atomic no-replace conflict")
            }
        }
        XCTAssertEqual(try Data(contentsOf: existing), Data([0xee]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: staging.directory.path))
        XCTAssertThrowsError(try staging.commitPreparedFile(to: root, name: FileTransferRelativePath("nested/file")))
        let committed = try staging.commitPreparedFile(to: root, name: FileTransferRelativePath("报告😀%20.txt"))
        XCTAssertEqual(try Data(contentsOf: committed), Data([1, 2]))
        XCTAssertEqual(try Data(contentsOf: committed.appendingPathComponent("..namedfork/rsrc")), Data([0, 0xff, 3]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.directory.path))
        staging.cancel()
        XCTAssertEqual(try Data(contentsOf: committed), Data([1, 2]))
        XCTAssertThrowsError(try staging.commitPreparedFile(to: root, name: FileTransferRelativePath("duplicate")))
    }

    func testCommitRejectsSymlinkDirectoryAndCannotReplaceExistingSymlink() throws {
        let root = try parent()
        defer { try? FileManager.default.removeItem(at: root) }
        let actual = root.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: actual, withIntermediateDirectories: false)
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: actual)
        let kept = actual.appendingPathComponent("kept")
        try Data([0xee]).write(to: kept)
        let occupied = actual.appendingPathComponent("occupied")
        try FileManager.default.createSymbolicLink(at: occupied, withDestinationURL: kept)
        let staging = try AppleFileCopyStagingFile(item: item(data: 0, resource: 0),
            sessionID: 7, parentDirectory: root, maximumFileBytes: 0)
        try staging.finish()
        XCTAssertThrowsError(try staging.commitPreparedFile(to: alias, name: FileTransferRelativePath("new")))
        XCTAssertThrowsError(try staging.commitPreparedFile(to: actual, name: FileTransferRelativePath("occupied")))
        XCTAssertEqual(try Data(contentsOf: kept), Data([0xee]))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: occupied.path), kept.path)
    }

    func testExtendedAttributeIsRestoredAsExactBinaryDataOnOwnedFile() throws {
        let root = try parent()
        defer { try? FileManager.default.removeItem(at: root) }
        let name = "com.aetherscreens.qa.binary"
        let key = Data(name.utf8) + Data([0])
        let value = Data([0, 0xff, 0, 0x80])
        var table = Data()
        for number in [UInt32(16 + key.count + value.count), 1, UInt32(key.count), UInt32(value.count)] {
            withUnsafeBytes(of: number.bigEndian) { table.append(contentsOf: $0) }
        }
        table.append(key); table.append(value)
        var envelope = Data([0x65, 0x78, 0x74, 0x31, 0, 0, 0, 1])
        withUnsafeBytes(of: UInt16(table.count + 10).bigEndian) { envelope.append(contentsOf: $0) }
        envelope.append(table)
        let staging = try AppleFileCopyStagingFile(item: item(data: 1, resource: 0, extensions: envelope),
            sessionID: 7, parentDirectory: root, maximumFileBytes: 1)
        try staging.append(raw(Data([0x42])), inflater: AppleFileCopyInflater())
        try staging.finish()
        var restored = Data(count: value.count)
        let count = staging.dataForkURL.withUnsafeFileSystemRepresentation { path in
            name.withCString { attribute in
                restored.withUnsafeMutableBytes { buffer in
                    getxattr(path!, attribute, buffer.baseAddress, buffer.count, 0, 0)
                }
            }
        }
        XCTAssertEqual(count, value.count)
        XCTAssertEqual(restored, value)
        XCTAssertEqual(try Data(contentsOf: staging.dataForkURL), Data([0x42]))
        let unsupported = try AppleFileCopyStagingFile(item: item(data: 0, resource: 0,
            extensions: Data([0xaa, 0xbb, 0xcc, 0xdd])), sessionID: 7,
            parentDirectory: root, maximumFileBytes: 0)
        XCTAssertThrowsError(try unsupported.finish())
        XCTAssertFalse(FileManager.default.fileExists(atPath: unsupported.directory.path))
        XCTAssertEqual(try Data(contentsOf: staging.dataForkURL), Data([0x42]))
    }

    func testLargeResourceForkStreamsExactlyAndTruncatedStagingCannotFinish() throws {
        let root = try parent()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = Data((0..<135111).map { UInt8(truncatingIfNeeded: $0 * 37) })
        let staging = try AppleFileCopyStagingFile(item: item(data: 0, resource: UInt64(source.count)),
            sessionID: 7, parentDirectory: root, maximumFileBytes: UInt64(source.count))
        try staging.append(raw(source), inflater: AppleFileCopyInflater())
        try staging.finish()
        XCTAssertEqual(try Data(contentsOf: staging.dataForkURL), Data())
        XCTAssertEqual(try Data(contentsOf: staging.dataForkURL.appendingPathComponent("..namedfork/rsrc")), source)

        let damaged = try AppleFileCopyStagingFile(item: item(data: 0, resource: 3),
            sessionID: 7, parentDirectory: root, maximumFileBytes: 3)
        try damaged.append(raw(Data([1, 2, 3])), inflater: AppleFileCopyInflater())
        try Data([1]).write(to: damaged.resourceForkURL)
        XCTAssertThrowsError(try damaged.finish())
        XCTAssertFalse(FileManager.default.fileExists(atPath: damaged.directory.path))
        XCTAssertEqual(try Data(contentsOf: staging.dataForkURL.appendingPathComponent("..namedfork/rsrc")), source)
    }
    #endif

    func testBudgetAndOverflowAreRejectedBeforeCreatingFiles() throws {
        let root = try parent()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try AppleFileCopyStagingFile(item: item(data: 4, resource: 2),
            sessionID: 7, parentDirectory: root, maximumFileBytes: 5))
        XCTAssertThrowsError(try AppleFileCopyStagingFile(item: item(data: UInt64.max, resource: 1),
            sessionID: 7, parentDirectory: root, maximumFileBytes: UInt64.max))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        var staging: AppleFileCopyStagingFile? = try AppleFileCopyStagingFile(
            item: item(data: 0, resource: 0), sessionID: 7, parentDirectory: root, maximumFileBytes: 0)
        let directory = try XCTUnwrap(staging).directory
        try staging?.finish()
        staging = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }
}
