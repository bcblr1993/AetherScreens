import XCTest
import CoreGraphics
@testable import AetherScreensCore

final class Phase21PerformanceAndThumbnailCacheTests: XCTestCase {

    func testDownsampleImageScales4KFrameWithinMaxPixelDimensionPreservingAspectRatio() throws {
        let width = 3840
        let height = 2160
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let source4K = try XCTUnwrap(context.makeImage())

        let downsampled = ThumbnailStore.downsampleImage(source4K, maxPixelDimension: 480)
        XCTAssertEqual(downsampled.width, 480)
        XCTAssertEqual(downsampled.height, 270)

        // Already small image should not be upscaled
        let small = ThumbnailStore.downsampleImage(downsampled, maxPixelDimension: 480)
        XCTAssertEqual(small.width, 480)
        XCTAssertEqual(small.height, 270)
    }

    func testThumbnailStoreMemoryCacheEvictionAndClear() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Phase21Thumbnails_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ThumbnailStore(cacheDirectory: tempDir)
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 640,
            height: 360,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())
        let id = UUID()

        store.saveThumbnail(image, for: id)
        let cached = try XCTUnwrap(store.cachedThumbnail(for: id))
        XCTAssertLessThanOrEqual(cached.width, 480)

        store.clearMemoryCache()
        XCTAssertNil(store.cachedThumbnail(for: id))
        // Disk fallback still works after memory cache is cleared
        XCTAssertNotNil(store.getThumbnail(for: id))
    }

    @MainActor
    func testPerformanceMetricsRoundedLatencyAndHUDChangeDetection() {
        let metrics = PerformanceMetrics()
        metrics.recordLatency(ms: 24.0)
        XCTAssertEqual(metrics.latencyMs, 24.0, accuracy: 0.05)

        // Sub-0.05ms jitter should round to the same 0.1ms bucket and not trigger extra publications
        var publishCount = 0
        let cancellable = metrics.objectWillChange.sink { publishCount += 1 }
        metrics.recordLatency(ms: 24.04)
        XCTAssertEqual(publishCount, 0)
        withExtendedLifetime(cancellable) {}

        XCTAssertFalse(metrics.hasMeaningfulHUDChange(previousFPS: 0, previousLatencyMs: 24, previousBandwidthKbps: 0))
        XCTAssertTrue(metrics.hasMeaningfulHUDChange(previousFPS: 60, previousLatencyMs: 24, previousBandwidthKbps: 0))
    }
}
