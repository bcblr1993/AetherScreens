import XCTest
@testable import AetherScreensCore

final class AppleFileCopyReceiveSessionTests: XCTestCase {
    func testUnsupportedAndConflictingKindsFailBeforeCreatingStaging() throws {
        for (kind, directory) in [(UInt8(0), false), (255, false), (3, false), (1, true), (2, false)] {
            let root = try root()
            defer { try? FileManager.default.removeItem(at: root) }
            let receiver = try AppleFileCopyReceiveSession(sessionID: 7, parentDirectory: root,
                maximumBytes: 0, maximumItems: 1)
            var body = item(data: 0).body
            body[0] = kind
            body[91] = directory ? 0x10 : 0
            XCTAssertThrowsError(try receiver.receive(.init(version: 1, command: 101,
                sessionID: 7, body: body)))
            XCTAssertEqual(receiver.state, .failed)
            XCTAssertTrue(receiver.manifest.entries.isEmpty)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        }
    }

    #if os(macOS)
    func testNestedPreparedTreeIsAssembledBeforeRootOwnershipHandoff() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let receiver = try AppleFileCopyReceiveSession(sessionID: 7, parentDirectory: root,
            maximumBytes: 2, maximumItems: 3)
        for level: UInt8 in [0, 1] {
            var folder = item(data: 0).body
            folder[0] = 2
            folder[91] = 0x10
            folder[93] = level
            _ = try receiver.receive(.init(version: 1, command: 101, sessionID: 7, body: folder))
        }
        var child = item(data: 2).body
        child[93] = 2
        _ = try receiver.receive(.init(version: 1, command: 101, sessionID: 7, body: child))
        _ = try receiver.receive(raw([11, 22]))
        _ = try receiver.receive(end())
        let trees = try receiver.takePreparedTrees()
        XCTAssertEqual(trees.count, 1)
        XCTAssertEqual(receiver.state, .handedOff)
        XCTAssertThrowsError(try receiver.takePreparedTrees())
        XCTAssertEqual(receiver.state, .handedOff)
        XCTAssertEqual(try Data(contentsOf: trees[0].dataForkURL.appendingPathComponent("A/A")), Data([11, 22]))
        receiver.cancel()
        XCTAssertTrue(FileManager.default.fileExists(atPath: trees[0].dataForkURL.path))
        let destination = try trees[0].commitPreparedFile(to: root)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("A/A")), Data([11, 22]))
        trees[0].cancel()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["A"])
    }
    #endif

    func testDirectoryAndChildFileKeepHierarchyAndPreparedContents() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let receiver = try AppleFileCopyReceiveSession(sessionID: 7, parentDirectory: root,
            maximumBytes: 2, maximumItems: 2)
        var folder = item(data: 0).body
        folder[0] = 2
        folder[91] = 0x10
        XCTAssertEqual(try receiver.receive(.init(version: 1, command: 101,
            sessionID: 7, body: folder)), .itemPrepared)
        var child = item(data: 2).body
        child[93] = 1
        XCTAssertEqual(try receiver.receive(.init(version: 1, command: 101,
            sessionID: 7, body: child)), .itemStarted)
        XCTAssertEqual(try receiver.receive(raw([11, 22])), .itemPrepared)
        XCTAssertEqual(receiver.manifest.entries.map { $0.path.path }, ["A", "A/A"])
        XCTAssertEqual(receiver.manifest.entries[1].parentIndex, 0)
        XCTAssertEqual(receiver.acknowledgedBytes, 2)
        XCTAssertEqual(try receiver.receive(end()), .senderFinished)
        let prepared = try receiver.takePreparedFiles()
        XCTAssertEqual(prepared.count, 2)
        var directory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared[0].dataForkURL.path, isDirectory: &directory))
        XCTAssertTrue(directory.boolValue)
        XCTAssertEqual(try Data(contentsOf: prepared[1].dataForkURL), Data([11, 22]))
        prepared.forEach { $0.cancel() }
        receiver.cancel()
        XCTAssertTrue(receiver.manifest.entries.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testMissingParentFailsAndClearsPreparedFilesAndManifest() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let receiver = try AppleFileCopyReceiveSession(sessionID: 7, parentDirectory: root,
            maximumBytes: 0, maximumItems: 2)
        XCTAssertEqual(try receiver.receive(item(data: 0)), .itemPrepared)
        XCTAssertEqual(receiver.manifest.entries.count, 1)
        var orphanBody = item(data: 0).body
        orphanBody[93] = 1
        XCTAssertThrowsError(try receiver.receive(.init(version: 1, command: 101,
            sessionID: 7, body: orphanBody)))
        XCTAssertEqual(receiver.state, .failed)
        XCTAssertTrue(receiver.manifest.entries.isEmpty)
        XCTAssertTrue(receiver.preparedFiles.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("receive-session-qa-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
    private func item(data: UInt64, resource: UInt64 = 0) -> AppleFileCopyMessage {
        var body = Data(repeating: 0, count: 104)
        body[0] = 1
        for (offset, count) in [(34, resource), (42, data)] {
            for index in 0..<8 { body[offset + index] = UInt8(truncatingIfNeeded: count >> ((7 - index) * 8)) }
        }
        body[101] = 1
        body.append(contentsOf: [65, 0])
        return .init(version: 1, command: 101, sessionID: 7, body: body)
    }
    private func raw(_ bytes: [UInt8], session: UInt32 = 7) -> AppleFileCopyMessage {
        var body = Data()
        withUnsafeBytes(of: UInt32(bytes.count).bigEndian) { body.append(contentsOf: $0) }
        body.append(contentsOf: bytes)
        return .init(version: 1, command: 102, sessionID: session, body: body)
    }
    private func end(_ bytes: [UInt8] = [0, 0, 0, 0]) -> AppleFileCopyMessage {
        .init(version: 1, command: 104, sessionID: 7, body: Data(bytes))
    }

    func testMultipleItemsRequireExplicitEndAndTransferStagingOwnership() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let receiver = try AppleFileCopyReceiveSession(sessionID: 7, parentDirectory: root, maximumBytes: 5, maximumItems: 2)
        XCTAssertEqual(try receiver.receive(item(data: 2, resource: 3)), .itemStarted)
        XCTAssertEqual(try receiver.receive(raw([9], session: 8)), .ignored)
        XCTAssertEqual(try receiver.receive(raw([1])), .bytesWritten(1))
        XCTAssertEqual(try receiver.receive(raw([2])), .bytesWritten(1))
        XCTAssertEqual(try receiver.receive(raw([3, 4, 5])), .itemPrepared)
        XCTAssertEqual(receiver.acknowledgedBytes, 5)
        XCTAssertEqual(try receiver.receive(item(data: 0)), .itemPrepared)
        XCTAssertThrowsError(try receiver.takePreparedFiles())
        XCTAssertEqual(receiver.state, .receiving)
        XCTAssertEqual(try receiver.receive(end()), .senderFinished)
        let files = try receiver.takePreparedFiles()
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(receiver.state, .handedOff)
        XCTAssertThrowsError(try receiver.takePreparedFiles())
        XCTAssertEqual(try Data(contentsOf: files[0].dataForkURL), Data([1, 2]))
        XCTAssertEqual(try Data(contentsOf: files[0].resourceForkURL), Data([3, 4, 5]))
        XCTAssertEqual(try Data(contentsOf: files[1].dataForkURL), Data())
        receiver.cancel()
        XCTAssertTrue(FileManager.default.fileExists(atPath: files[0].dataForkURL.path))
        files.forEach { $0.cancel() }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testCompressedDictionaryContinuesAcrossPreparedItemBoundary() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = Data((0..<65536).map { UInt8(truncatingIfNeeded: $0 * 37) })
        let second = Data(first.suffix(32768))
        let deflater = try ZRLETestDeflater()
        let firstPacket = try deflater.compress(first)
        let secondPacket = try deflater.compress(second)
        XCTAssertThrowsError(try AppleFileCopyInflater().expand(
            .compressed(algorithm: 1, expandedBytes: UInt32(second.count), payload: secondPacket)))
        func compressed(_ packet: Data, expanded: Int) -> AppleFileCopyMessage {
            var body = Data([0, 1])
            for size in [UInt32(expanded), UInt32(packet.count)] {
                withUnsafeBytes(of: size.bigEndian) { body.append(contentsOf: $0) }
            }
            body.append(packet)
            return .init(version: 1, command: 103, sessionID: 7, body: body)
        }
        let receiver = try AppleFileCopyReceiveSession(sessionID: 7, parentDirectory: root,
            maximumBytes: UInt64(first.count + second.count), maximumItems: 2)
        XCTAssertEqual(try receiver.receive(item(data: UInt64(first.count))), .itemStarted)
        XCTAssertEqual(try receiver.receive(compressed(firstPacket, expanded: first.count)), .itemPrepared)
        XCTAssertEqual(try receiver.receive(item(data: UInt64(second.count))), .itemStarted)
        XCTAssertEqual(try receiver.receive(compressed(secondPacket, expanded: second.count)), .itemPrepared)
        XCTAssertEqual(try receiver.receive(end()), .senderFinished)
        let files = try receiver.takePreparedFiles()
        defer { files.forEach { $0.cancel() } }
        XCTAssertEqual(try Data(contentsOf: files[0].dataForkURL), first)
        XCTAssertEqual(try Data(contentsOf: files[1].dataForkURL), second)
        XCTAssertEqual(receiver.acknowledgedBytes, UInt64(first.count + second.count))
    }

    func testPrematureNextItemCancelsActiveAndPreparedFilesOnly() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let unrelated = root.appendingPathComponent("unrelated")
        try Data([99]).write(to: unrelated)
        let receiver = try AppleFileCopyReceiveSession(sessionID: 7, parentDirectory: root, maximumBytes: 10, maximumItems: 3)
        XCTAssertEqual(try receiver.receive(item(data: 0)), .itemPrepared)
        XCTAssertEqual(try receiver.receive(item(data: 2)), .itemStarted)
        XCTAssertEqual(try receiver.receive(raw([1])), .bytesWritten(1))
        XCTAssertThrowsError(try receiver.receive(item(data: 0)))
        XCTAssertEqual(receiver.state, .failed)
        XCTAssertTrue(receiver.preparedFiles.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["unrelated"])
        XCTAssertEqual(try Data(contentsOf: unrelated), Data([99]))
        XCTAssertThrowsError(try receiver.receive(end()))
    }

    func testMissingOrFailedEndAndBudgetsDoNotProducePreparedOutput() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        for result in [[], [1, 0, 0, 0]] as [[UInt8]] {
            let receiver = try AppleFileCopyReceiveSession(sessionID: 7, parentDirectory: root, maximumBytes: 1, maximumItems: 1)
            XCTAssertEqual(try receiver.receive(item(data: 0)), .itemPrepared)
            XCTAssertThrowsError(try receiver.receive(end(result)))
            XCTAssertEqual(receiver.state, .failed)
            XCTAssertThrowsError(try receiver.takePreparedFiles())
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        }
        let bytes = try AppleFileCopyReceiveSession(sessionID: 7, parentDirectory: root, maximumBytes: 1, maximumItems: 1)
        XCTAssertThrowsError(try bytes.receive(item(data: 2)))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        let items = try AppleFileCopyReceiveSession(sessionID: 7, parentDirectory: root, maximumBytes: 1, maximumItems: 1)
        XCTAssertEqual(try items.receive(item(data: 0)), .itemPrepared)
        XCTAssertThrowsError(try items.receive(item(data: 0)))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
}
