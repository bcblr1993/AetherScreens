import XCTest
import CoreGraphics
import ImageIO
@testable import AetherScreensCore

final class AsyncThumbnailTests: XCTestCase {
    func testCancelledQueuedLoadDoesNotDecodeOrPopulateCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("thumbnail-qa-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        ThumbnailStore(cacheDirectory: directory).saveThumbnail(try image(width: 200, height: 100), for: id)
        let queue = DispatchQueue(label: "thumbnail-cancellation-qa")
        queue.suspend()
        let store = ThumbnailStore(cacheDirectory: directory, loadingQueue: queue)
        let started = expectation(description: "Load task started")
        let task = Task {
            started.fulfill()
            return await store.loadThumbnail(for: id)
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        queue.resume()
        let cancelled = await task.value
        XCTAssertNil(cancelled)
        XCTAssertNil(store.cachedThumbnail(for: id))
        let retry = await store.loadThumbnail(for: id)
        XCTAssertEqual(retry?.width, 200)
        XCTAssertNotNil(store.cachedThumbnail(for: id))
    }

    func testRemovalDeletesPersistedPreviewAndRejectsLateSessionSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("thumbnail-qa-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailStore(cacheDirectory: directory), id = UUID()
        let source = try image(width: 200, height: 100)
        store.saveThumbnail(source, for: id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(id).jpg").path))
        store.removeThumbnail(for: id)
        store.saveThumbnail(source, for: id)
        XCTAssertNil(store.cachedThumbnail(for: id))
        let loaded = await store.loadThumbnail(for: id)
        XCTAssertNil(loaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(id).jpg").path))
    }

    private func image(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    func testAsyncDiskLoadRestoresPreviewAndPopulatesMemoryCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("thumbnail-qa-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        ThumbnailStore(cacheDirectory: directory).saveThumbnail(try image(width: 1920, height: 1080), for: id)
        let cold = ThumbnailStore(cacheDirectory: directory)
        XCTAssertNil(cold.cachedThumbnail(for: id))
        let loaded = await cold.loadThumbnail(for: id)
        XCTAssertEqual(loaded?.width, 480)
        XCTAssertEqual(loaded?.height, 270)
        XCTAssertNotNil(cold.cachedThumbnail(for: id))
    }

    func testLegacyPortraitPNGIsDecodedAsBoundedPreview() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("thumbnail-qa-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailStore(cacheDirectory: directory), id = UUID()
        let file = directory.appendingPathComponent("\(id).png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try image(width: 600, height: 2400), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let loaded = await store.loadThumbnail(for: id)
        XCTAssertEqual(loaded?.width, 120)
        XCTAssertEqual(loaded?.height, 480)
    }

    func testMissingOrCorruptPreviewRemainsPlaceholder() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("thumbnail-qa-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailStore(cacheDirectory: directory), id = UUID()
        let missing = await store.loadThumbnail(for: id)
        XCTAssertNil(missing)
        try Data([0, 1, 2]).write(to: directory.appendingPathComponent("\(id).jpg"))
        let corrupt = await store.loadThumbnail(for: id)
        XCTAssertNil(corrupt)
        XCTAssertNil(store.cachedThumbnail(for: id))
    }
}
