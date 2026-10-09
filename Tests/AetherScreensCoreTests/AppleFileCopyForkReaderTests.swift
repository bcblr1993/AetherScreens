import XCTest
@testable import AetherScreensCore

final class AppleFileCopyForkReaderTests: XCTestCase {
    #if os(macOS)
    func testRealForkReaderFeedsReceiverAndCommitsBothForksWithoutChangingSources() throws {
        try withRoot { root in
            let data = root.appendingPathComponent("source"), resource = root.appendingPathComponent("sidecar")
            let original = Data([0, 255, 65, 66, 67]), resourceBytes = Data([128, 0, 1])
            try original.write(to: data); try resourceBytes.write(to: resource)
            let metadata = item(data: 5, resource: 3)
            let reader = try AppleFileCopyForkReader(item: metadata, sessionID: 42,
                dataURL: data, resourceURL: resource, blockSize: 2)
            let receiver = try AppleFileCopyReceiveSession(sessionID: 42, parentDirectory: root,
                maximumBytes: 8, maximumItems: 1)
            defer { receiver.cancel(); reader.cancel() }
            _ = try receiver.receive(metadata.message(sessionID: 42))
            while let message = try reader.nextMessage() { _ = try receiver.receive(message) }
            XCTAssertEqual(receiver.acknowledgedBytes, 8)
            _ = try receiver.receive(.init(version: 1, command: 104, sessionID: 42,
                                          body: Data([0, 0, 0, 0])))
            let prepared = try receiver.takePreparedTrees()
            XCTAssertEqual(prepared.count, 1)
            let destination = try prepared[0].commitPreparedFile(to: root)
            XCTAssertEqual(try Data(contentsOf: destination), original)
            XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("..namedfork/rsrc")), resourceBytes)
            receiver.cancel()
            XCTAssertEqual(try Data(contentsOf: data), original)
            XCTAssertEqual(try Data(contentsOf: resource), resourceBytes)
            XCTAssertEqual(try Data(contentsOf: destination), original)
        }
    }
    #endif

    private func item(data: UInt64, resource: UInt64 = 0) -> AppleFileCopyItem {
        var header = Data(repeating: 0, count: 104)
        header[0] = 1
        withUnsafeBytes(of: resource.bigEndian) { header.replaceSubrange(34..<42, with: $0) }
        withUnsafeBytes(of: data.bigEndian) { header.replaceSubrange(42..<50, with: $0) }
        return .init(catalogHeader: header, level: 0, wireName: "QA",
                     symbolicLinkTarget: nil, extensions: Data())
    }

    private func withRoot(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aetherscreens-upload-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    func testBoundedDataThenResourcePacketsRetainBinaryBytes() throws {
        try withRoot { root in
            let data = root.appendingPathComponent("data"), resource = root.appendingPathComponent("resource")
            try Data([0, 255, 65, 66, 67]).write(to: data)
            try Data([128, 0, 1]).write(to: resource)
            let reader = try AppleFileCopyForkReader(item: item(data: 5, resource: 3), sessionID: 42,
                dataURL: data, resourceURL: resource, blockSize: 2)
            var actual: [Data] = []
            while let message = try reader.nextMessage() {
                XCTAssertEqual(message.command, 102)
                XCTAssertEqual(message.sessionID, 42)
                guard case .raw(let bytes) = try AppleFileCopyDataBlock.decode(message,
                    expectedSessionID: 42, remainingForkBytes: 8) else { return XCTFail("Raw data expected") }
                actual.append(bytes)
                XCTAssertLessThanOrEqual(message.body.count, 6)
            }
            XCTAssertEqual(actual, [Data([0, 255]), Data([65, 66]), Data([67]), Data([128, 0]), Data([1])])
            XCTAssertNil(try reader.nextMessage())
            reader.cancel()
            XCTAssertThrowsError(try reader.nextMessage())
            XCTAssertEqual(try Data(contentsOf: data), Data([0, 255, 65, 66, 67]))
        }
    }

    func testEmptyDataForkMovesToResourceAndSourceReplacementKeepsOpenedFile() throws {
        try withRoot { root in
            let data = root.appendingPathComponent("data"), resource = root.appendingPathComponent("resource")
            try Data().write(to: data); try Data([11, 22]).write(to: resource)
            let reader = try AppleFileCopyForkReader(item: item(data: 0, resource: 2), sessionID: 1,
                dataURL: data, resourceURL: resource, blockSize: 2)
            try FileManager.default.moveItem(at: resource, to: root.appendingPathComponent("old"))
            try Data([99, 99]).write(to: resource)
            XCTAssertEqual(try reader.nextMessage()?.body, Data([0, 0, 0, 2, 11, 22]))
            XCTAssertNil(try reader.nextMessage())
        }
    }

    func testRejectsSymlinksDirectoriesSizeMismatchAndMissingResource() throws {
        try withRoot { root in
            let data = root.appendingPathComponent("data"), link = root.appendingPathComponent("link")
            try Data([1]).write(to: data)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: data)
            for url in [root, link] {
                XCTAssertThrowsError(try AppleFileCopyForkReader(item: item(data: 1), sessionID: 1,
                    dataURL: url, resourceURL: nil))
            }
            XCTAssertThrowsError(try AppleFileCopyForkReader(item: item(data: 2), sessionID: 1,
                dataURL: data, resourceURL: nil))
            XCTAssertThrowsError(try AppleFileCopyForkReader(item: item(data: 1, resource: 1), sessionID: 1,
                dataURL: data, resourceURL: nil))
            for size in [0, -1, 1_048_565] {
                XCTAssertThrowsError(try AppleFileCopyForkReader(item: item(data: 1), sessionID: 1,
                    dataURL: data, resourceURL: nil, blockSize: size))
            }
            XCTAssertEqual(try Data(contentsOf: data), Data([1]))
        }
    }

    func testSourceTruncationFailsAndClosesAttemptWithoutSendingEndMarker() throws {
        try withRoot { root in
            let data = root.appendingPathComponent("data")
            try Data([1, 2, 3, 4]).write(to: data)
            let reader = try AppleFileCopyForkReader(item: item(data: 4), sessionID: 1,
                dataURL: data, resourceURL: nil, blockSize: 2)
            XCTAssertEqual(try reader.nextMessage()?.body, Data([0, 0, 0, 2, 1, 2]))
            let writer = try FileHandle(forWritingTo: data)
            try writer.truncate(atOffset: 2); try writer.close()
            XCTAssertThrowsError(try reader.nextMessage())
            XCTAssertThrowsError(try reader.nextMessage())
            XCTAssertEqual(try Data(contentsOf: data), Data([1, 2]))
        }
    }
}
