#if os(macOS)
import XCTest
@testable import AetherScreensCore

final class AppleFileCopyUploadPreparationTests: XCTestCase {
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("upload-preparation-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    func testCompletePreorderPreservesHiddenEmptyAndNestedFilesAndForks() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let child = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        try Data().write(to: root.appendingPathComponent("empty.bin"))
        try Data([42]).write(to: root.appendingPathComponent(".hidden"))
        let file = child.appendingPathComponent("测试😀.bin")
        try Data([0,1,2,3,4]).write(to: file)
        try Data([6,7]).write(to: file.appendingPathComponent("..namedfork/rsrc"))
        let prepared = try AppleFileCopyUploadPreparation.collect(url: root)
        XCTAssertEqual(prepared.sources.count, 5)
        XCTAssertEqual(prepared.logicalBytes, 8)
        XCTAssertEqual(prepared.fileCount, 3)
        XCTAssertEqual(prepared.folderCount, 2)
        XCTAssertEqual(prepared.forkCount, 3)
        let index = try XCTUnwrap(prepared.sources.firstIndex { $0.item.wireName == "nested" })
        XCTAssertEqual(prepared.sources[index].item.level, 1)
        XCTAssertEqual(prepared.sources[index + 1].item.wireName, "测试😀.bin")
        XCTAssertEqual(prepared.sources[index + 1].item.level, 2)
        XCTAssertTrue(prepared.sources.contains { $0.item.wireName == ".hidden" })
        XCTAssertEqual(try Data(contentsOf: file), Data([0,1,2,3,4]))
    }

    func testLimitsRejectWholePreparationRatherThanTruncatingTree() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        try Data([1,2]).write(to: root.appendingPathComponent("file"))
        for limits in [(1,64,UInt64(100)),(1024,0,100),(1024,64,1)] {
            XCTAssertThrowsError(try AppleFileCopyUploadPreparation.collect(url: root,
                maximumItems: limits.0, maximumDepth: limits.1, maximumBytes: limits.2))
        }
        XCTAssertThrowsError(try AppleFileCopyUploadPreparation.collect(url: root, maximumItems: 0))
    }

    func testSymbolicLinksAreRejectedWithoutReadingTheirTargets() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let outside = try self.root(); defer { try? FileManager.default.removeItem(at: outside) }
        let target = outside.appendingPathComponent("private")
        try Data([9,8,7]).write(to: target)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: target)
        XCTAssertThrowsError(try AppleFileCopyUploadPreparation.collect(url: root))
        XCTAssertEqual(try Data(contentsOf: target), Data([9,8,7]))
    }

    func testCancellationStopsBeforeCollection() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try AppleFileCopyUploadPreparation.collect(url: root, isCancelled: { true }))
    }
}
#endif
