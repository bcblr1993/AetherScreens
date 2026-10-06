import XCTest
import CoreGraphics
@testable import AetherScreensCore

final class ThumbnailStoreTests: XCTestCase {
    private var store: ThumbnailStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        store = try ThumbnailStore.makeTemporary()
    }

    override func tearDown() {
        store = nil
        super.tearDown()
    }

    func testThumbnailSaveAndRetrieve() {
        let store = self.store!
        let testId = UUID()

        // Create a 100x100 dummy test CGImage
        let width = 100
        let height = 100
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rawData = [UInt8](repeating: 200, count: width * height * 4)
        let provider = CGDataProvider(data: Data(rawData) as CFData)!
        let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!

        store.saveThumbnail(cgImage, for: testId)
        let retrieved = store.getThumbnail(for: testId)

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.width, width)
        XCTAssertEqual(retrieved?.height, height)
        let reopened = ThumbnailStore(cacheDirectory: store.directoryURL)
        XCTAssertEqual(reopened.getThumbnail(for: testId)?.width, width)
        XCTAssertEqual(reopened.getThumbnail(for: testId)?.height, height)
    }

    func testLargeDesktopIsStoredAsCompactPreview() {
        let width = 1920
        let height = 1080
        let bytes = Data(repeating: 120, count: width * height * 4)
        let provider = CGDataProvider(data: bytes as CFData)!
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        let id = UUID()

        store.saveThumbnail(image, for: id)
        let preview = store.getThumbnail(for: id)
        XCTAssertEqual(preview?.width, 480)
        XCTAssertEqual(preview?.height, 270)
    }

    func testTemporaryCacheCleanupRemovesOnlyItsOwnRootAndDoesNotFollowChildSymlink() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: parent) }
        let outside = parent.appendingPathComponent("preserved.txt")
        let sentinel = Data("synthetic-outside-cache".utf8)
        try sentinel.write(to: outside)
        var privateStore: ThumbnailStore? = try ThumbnailStore.makeTemporary(parentDirectory: parent)
        let cache = try XCTUnwrap(privateStore?.directoryURL)
        try FileManager.default.createSymbolicLink(at: cache.appendingPathComponent("external-link"), withDestinationURL: outside)
        try Data([1, 2, 3]).write(to: cache.appendingPathComponent("synthetic.jpg"))
        privateStore = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertEqual(try Data(contentsOf: outside), sentinel)
    }

    func testTemporaryCacheCleanupPreservesReplacementRootAndDoesNotTraverseChildDirectories() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: parent) }
        var privateStore: ThumbnailStore? = try ThumbnailStore.makeTemporary(parentDirectory: parent)
        let original = try XCTUnwrap(privateStore?.directoryURL)
        let moved = parent.appendingPathComponent("moved-owned-cache", isDirectory: true)
        let protected = parent.appendingPathComponent("protected", isDirectory: true)
        try FileManager.default.createDirectory(at: protected, withIntermediateDirectories: false)
        let sentinel = protected.appendingPathComponent("sentinel.txt")
        try Data("synthetic-protected".utf8).write(to: sentinel)
        try FileManager.default.moveItem(at: original, to: moved)
        try FileManager.default.createSymbolicLink(at: original, withDestinationURL: protected)
        privateStore = nil
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path))
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("synthetic-protected".utf8))
        XCTAssertTrue(try original.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)

        var nestedStore: ThumbnailStore? = try ThumbnailStore.makeTemporary(parentDirectory: parent)
        let nestedRoot = try XCTUnwrap(nestedStore?.directoryURL)
        let nested = nestedRoot.appendingPathComponent("unexpected-child", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        let nestedSentinel = nested.appendingPathComponent("keep.txt")
        try Data([7]).write(to: nestedSentinel)
        nestedStore = nil
        XCTAssertEqual(try Data(contentsOf: nestedSentinel), Data([7]), "The flat cache lease must never recurse into a child directory")
    }
}
