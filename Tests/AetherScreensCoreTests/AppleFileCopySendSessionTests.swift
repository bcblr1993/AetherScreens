import XCTest
@testable import AetherScreensCore

final class AppleFileCopySendSessionTests: XCTestCase {
    func testUnknownSymlinkAndContradictoryKindsCannotStartOrdinaryUpload() throws {
        try withSource { _, source in
            for (kind, flags): (UInt8, UInt8) in [(0, 0), (3, 0), (2, 0), (1, 0x10)] {
                var header = source.item.catalogHeader
                header[0] = kind; header[91] = flags
                let item = AppleFileCopyItem(catalogHeader: header, level: 0, wireName: "QA",
                    symbolicLinkTarget: nil, extensions: Data())
                XCTAssertThrowsError(try AppleFileCopySendSession(sessionID: 42, sources: [
                    .init(item: item, dataURL: source.dataURL, resourceURL: nil)], maximumBytes: 5))
            }
            XCTAssertEqual(try Data(contentsOf: source.dataURL!), Data([0,255,65,66,67]))
        }
    }

    #if os(macOS)
    func testDirectoryAndChildSendInManifestOrderAndAssembleBeforeCommit() throws {
        try withSource { root, source in
            var folderHeader = Data(repeating: 0, count: 104); folderHeader[0] = 2; folderHeader[91] = 0x10
            let folder = AppleFileCopyItem(catalogHeader: folderHeader, level: 0, wireName: "folder",
                symbolicLinkTarget: nil, extensions: Data())
            let child = AppleFileCopyItem(catalogHeader: source.item.catalogHeader, level: 1,
                wireName: "QA", symbolicLinkTarget: nil, extensions: Data())
            let sender = try AppleFileCopySendSession(sessionID: 42, sources: [
                .init(item: folder, dataURL: nil, resourceURL: nil),
                .init(item: child, dataURL: source.dataURL, resourceURL: nil)], maximumBytes: 5)
            let receiver = try AppleFileCopyReceiveSession(sessionID: 42, parentDirectory: root,
                maximumBytes: 5, maximumItems: 2)
            defer { receiver.cancel() }
            while sender.state == .sending {
                var packet: AppleFileCopyMessage?
                XCTAssertTrue(try sender.pump { packet = $0; return true })
                _ = try receiver.receive(XCTUnwrap(packet))
            }
            let trees = try receiver.takePreparedTrees()
            XCTAssertEqual(trees.count, 1)
            let destination = try trees[0].commitPreparedFile(to: root)
            XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("QA")), Data([0, 255, 65, 66, 67]))
            XCTAssertEqual(sender.state, .awaitingResult)
            XCTAssertTrue(try sender.receive(result()))
        }
    }
    #endif

    private func withSource(_ body: (URL, AppleFileCopySendSession.Source) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aetherscreens-send-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("source")
        try Data([0, 255, 65, 66, 67]).write(to: url)
        var header = Data(repeating: 0, count: 104); header[0] = 1; header[49] = 5
        let item = AppleFileCopyItem(catalogHeader: header, level: 0, wireName: "QA",
            symbolicLinkTarget: nil, extensions: Data())
        try body(root, .init(item: item, dataURL: url, resourceURL: nil))
    }

    private func result(session: UInt32 = 42, error: UInt8 = 0) -> AppleFileCopyMessage {
        .init(version: 1, command: 200, sessionID: session, body: Data([0, error, 0, 2, 81, 65, 0]))
    }

    func testEveryPacketRetriesIdenticallyAndCompletionRequiresRemoteResult() throws {
        try withSource { root, source in
            let sender = try AppleFileCopySendSession(sessionID: 42, sources: [source], maximumBytes: 5, blockSize: 2)
            let receiver = try AppleFileCopyReceiveSession(sessionID: 42, parentDirectory: root,
                maximumBytes: 5, maximumItems: 1)
            defer { receiver.cancel() }
            var commands: [UInt16] = []
            while sender.state == .sending {
                var rejected: AppleFileCopyMessage?
                XCTAssertFalse(try sender.pump { rejected = $0; return false })
                var accepted: AppleFileCopyMessage?
                XCTAssertTrue(try sender.pump { accepted = $0; return true })
                XCTAssertEqual(accepted, rejected)
                let packet = try XCTUnwrap(accepted)
                _ = try receiver.receive(packet)
                commands.append(packet.command)
            }
            XCTAssertEqual(commands, [101, 102, 102, 102, 104])
            XCTAssertEqual(sender.queuedBytes, 5)
            XCTAssertEqual(sender.state, .awaitingResult)
            XCTAssertNil(sender.destinationName)
            XCTAssertFalse(try sender.receive(result(session: 99)))
            XCTAssertTrue(try sender.receive(result()))
            XCTAssertEqual(sender.state, .completed)
            XCTAssertEqual(sender.destinationName, Data([81, 65]))
            XCTAssertEqual(receiver.acknowledgedBytes, 5)
            let files = try receiver.takePreparedFiles()
            XCTAssertEqual(try Data(contentsOf: files[0].dataForkURL), Data([0, 255, 65, 66, 67]))
            files.forEach { $0.cancel() }
            XCTAssertFalse(try sender.receive(result()))
        }
    }

    func testPrematureSuccessAndRemoteErrorFailInsteadOfCompleting() throws {
        try withSource { _, source in
            let early = try AppleFileCopySendSession(sessionID: 42, sources: [source], maximumBytes: 5)
            XCTAssertThrowsError(try early.receive(result()))
            XCTAssertEqual(early.state, .failed)
            let failed = try AppleFileCopySendSession(sessionID: 42, sources: [source], maximumBytes: 5)
            while failed.state == .sending { XCTAssertTrue(try failed.pump { _ in true }) }
            XCTAssertThrowsError(try failed.receive(result(error: 1)))
            XCTAssertEqual(failed.state, .failed)
            XCTAssertNil(failed.destinationName)
        }
    }

    func testReentrantCancellationInvalidatesAdmissionAndStopsFurtherReads() throws {
        try withSource { _, source in
            let sender = try AppleFileCopySendSession(sessionID: 42, sources: [source], maximumBytes: 5)
            XCTAssertTrue(try sender.pump { _ in true }) // item header
            XCTAssertFalse(try sender.pump { _ in sender.cancel(); return true })
            XCTAssertEqual(sender.state, .cancelled)
            XCTAssertEqual(sender.queuedBytes, 0)
            XCTAssertThrowsError(try sender.pump { _ in XCTFail("No send after cancel"); return true })
            XCTAssertFalse(try sender.receive(result()))
            XCTAssertEqual(try Data(contentsOf: source.dataURL!), Data([0, 255, 65, 66, 67]))
        }
    }

    func testBudgetAndChangedSourceFailBeforeSendingHeader() throws {
        try withSource { _, source in
            XCTAssertThrowsError(try AppleFileCopySendSession(sessionID: 42, sources: [source], maximumBytes: 4))
            let sender = try AppleFileCopySendSession(sessionID: 42, sources: [source], maximumBytes: 5)
            try Data([1]).write(to: source.dataURL!)
            XCTAssertThrowsError(try sender.pump { _ in XCTFail("Invalid source must not send"); return true })
            XCTAssertEqual(sender.state, .failed)
        }
    }
}
