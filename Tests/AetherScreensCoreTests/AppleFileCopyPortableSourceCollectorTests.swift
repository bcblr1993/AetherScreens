#if os(macOS)
import XCTest
import Darwin
@testable import AetherScreensCore

final class AppleFileCopyPortableSourceCollectorTests: XCTestCase {
    func testPortableCatalogPreservesNativeFinderForksDatesAndPermissions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portable-source-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("测试😀.bin")
        try Data([0,1,2,3,4]).write(to: file)
        try Data([9,8]).write(to: file.appendingPathComponent("..namedfork/rsrc"))
        for url in [root, file] {
            let finder = Data([65,66,67,68,69,70,71,72] + [UInt8](repeating: 0, count: 24))
            let result = url.withUnsafeFileSystemRepresentation { path in
                finder.withUnsafeBytes { setxattr(path!, "com.apple.FinderInfo", $0.baseAddress, finder.count, 0, XATTR_NOFOLLOW) }
            }
            XCTAssertEqual(result, 0)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_600_000_000.5)], ofItemAtPath: url.path)
            let portable = try AppleFileCopyPortableSourceCollector.collect(url: url, level: 1)
            let native = try AppleFileCopySourceCollector.collect(url: url, level: 1)
            let actual = try AppleFileCopyCatalogMetadata.decode(portable.item.catalogHeader)
            let expected = try AppleFileCopyCatalogMetadata.decode(native.item.catalogHeader)
            XCTAssertEqual(actual.wireFinderInfo, expected.wireFinderInfo)
            XCTAssertEqual(actual.finderInfoAttribute, finder)
            XCTAssertEqual(actual.permissionMode, expected.permissionMode)
            // Carbon quantizes the observed filesystem fraction one wire tick
            // lower on this fixture. Compare at the protocol's 16-bit precision.
            XCTAssertEqual(actual.contentModified.date.timeIntervalSince1970,
                           expected.contentModified.date.timeIntervalSince1970, accuracy: 1.0 / 65536)
            XCTAssertEqual(actual.created.date.timeIntervalSince1970, expected.created.date.timeIntervalSince1970, accuracy: 1.0 / 65536)
            XCTAssertEqual(portable.item.dataForkByteCount, native.item.dataForkByteCount)
            XCTAssertEqual(portable.item.resourceForkByteCount, native.item.resourceForkByteCount)
            XCTAssertEqual(portable.item.wireName, native.item.wireName)
            let attributes = try XCTUnwrap(AppleFileCopyAttributeBlock.decode(portable.item.extensions)?.entries())
            XCTAssertEqual(attributes.first { $0.name == Data("com.apple.FinderInfo".utf8) }?.value, finder)
        }
        XCTAssertEqual(try Data(contentsOf: file), Data([0,1,2,3,4]))
    }

    func testSymbolicLinkAndMissingSourceAreRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portable-link-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("file")
        try Data([1]).write(to: file)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertThrowsError(try AppleFileCopyPortableSourceCollector.collect(url: link, level: 0))
        XCTAssertThrowsError(try AppleFileCopyPortableSourceCollector.collect(url: root.appendingPathComponent("missing"), level: 0))
    }
}
#endif
