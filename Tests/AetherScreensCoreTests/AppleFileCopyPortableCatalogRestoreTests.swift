#if os(macOS)
import XCTest
import Darwin
@testable import AetherScreensCore

final class AppleFileCopyPortableCatalogRestoreTests: XCTestCase {
    func testRestoresFileAndDirectoryFinderInfoAndDatesWithoutCarbon() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portable-restore-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        for directory in [false, true] {
            let source = root.appendingPathComponent(directory ? "source-dir" : "source-file")
            let target = root.appendingPathComponent(directory ? "target-dir" : "target-file")
            if directory {
                try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            } else {
                try Data([1,2]).write(to: source)
                try Data([9,8]).write(to: target)
            }
            let finder = Data((0..<32).map { UInt8($0) })
            let sourceFD = open(source.path, O_RDONLY | O_NOFOLLOW)
            guard sourceFD >= 0 else { return XCTFail("Cannot open fixture") }
            defer { close(sourceFD) }
            XCTAssertEqual(finder.withUnsafeBytes { fsetxattr(sourceFD, "com.apple.FinderInfo", $0.baseAddress, $0.count, 0, 0) }, 0)
            try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: 1_700_000_000),
                .modificationDate: Date(timeIntervalSince1970: 1_700_000_100)], ofItemAtPath: source.path)
            let item = try AppleFileCopySourceCollector.collect(url: source, level: 0).item
            let metadata = try AppleFileCopyCatalogMetadata.decode(item.catalogHeader)
            let targetFD = open(target.path, O_RDONLY | O_NOFOLLOW)
            guard targetFD >= 0 else { return XCTFail("Cannot open target") }
            defer { close(targetFD) }
            try AppleFileCopyPortableCatalogRestore.restore(metadata, descriptor: targetFD)
            var info = stat()
            XCTAssertEqual(fstat(targetFD, &info), 0)
            XCTAssertEqual(Double(info.st_birthtimespec.tv_sec) + Double(info.st_birthtimespec.tv_nsec) / 1e9,
                           metadata.created.date.timeIntervalSince1970, accuracy: 1.0 / 65_536)
            XCTAssertEqual(Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9,
                           metadata.contentModified.date.timeIntervalSince1970, accuracy: 1.0 / 65_536)
            var observed = Data(count: 32)
            XCTAssertEqual(observed.withUnsafeMutableBytes { fgetxattr(targetFD, "com.apple.FinderInfo", $0.baseAddress, $0.count, 0, 0) }, 32)
            XCTAssertEqual(observed, metadata.finderInfoAttribute)
            if !directory { XCTAssertEqual(try Data(contentsOf: target), Data([9,8])) }
            let wrongKind = try AppleFileCopyCatalogMetadata.decode(
                AppleFileCopySourceCollector.collect(url: root, level: 0).item.catalogHeader)
            if !directory { XCTAssertThrowsError(try AppleFileCopyPortableCatalogRestore.restore(wrongKind, descriptor: targetFD)) }
        }
    }
}
#endif
