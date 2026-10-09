import XCTest
import Metal
@testable import AetherScreensCore

final class MetalUploadBufferPoolTests: XCTestCase {
    func testIdleCapacityIsBoundedAndLeasedBuffersAreExclusive() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Requires Metal") }
        let pool = MetalUploadBufferPool(device: device, byteLimit: 1024, countLimit: 2)
        let a = try XCTUnwrap(pool.take(length: 512))
        let b = try XCTUnwrap(pool.take(length: 512))
        XCTAssertFalse(a === b)
        pool.recycle(a); pool.recycle(b)
        XCTAssertEqual(pool.cachedBytes, 1024)
        let excess = try XCTUnwrap(device.makeBuffer(length: 512, options: .storageModeShared))
        pool.recycle(excess)
        XCTAssertEqual(pool.cachedCount, 2)
        let first = try XCTUnwrap(pool.take(length: 256))
        let second = try XCTUnwrap(pool.take(length: 256))
        XCTAssertFalse(first === second)
        XCTAssertTrue(first === a || first === b)
        XCTAssertTrue(second === a || second === b)
        XCTAssertEqual(pool.cachedBytes, 0)
        let oversized = try XCTUnwrap(pool.take(length: 2048))
        pool.recycle(oversized)
        XCTAssertEqual(pool.cachedCount, 0)
    }

    func testDisabledCacheDropsIdleAndLateCompletionBuffers() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Requires Metal") }
        let pool = MetalUploadBufferPool(device: device)
        let idle = try XCTUnwrap(pool.take(length: 4096))
        let outstanding = try XCTUnwrap(pool.take(length: 4096))
        pool.recycle(idle)
        pool.setCachingEnabled(false)
        XCTAssertEqual(pool.cachedBytes, 0)
        pool.recycle(outstanding)
        XCTAssertEqual(pool.cachedCount, 0)
        let uncached = try XCTUnwrap(pool.take(length: 4096))
        pool.recycle(uncached)
        XCTAssertEqual(pool.cachedCount, 0)
        pool.setCachingEnabled(true)
        let resumed = try XCTUnwrap(pool.take(length: 4096))
        pool.recycle(resumed)
        XCTAssertEqual(pool.cachedBytes, 4096)
    }

    func testRepeatedFullDesktopUploadsReuseCompletedAllocation() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Requires Metal") }
        let pool = MetalUploadBufferPool(device: device)
        let bytes = 3840 * 2160 * 4
        let initial = try XCTUnwrap(pool.take(length: bytes))
        pool.recycle(initial)
        for _ in 0..<120 {
            let next = try XCTUnwrap(pool.take(length: bytes))
            XCTAssertTrue(next === initial)
            pool.recycle(next)
        }
        XCTAssertEqual(pool.cachedCount, 1)
        XCTAssertEqual(pool.cachedBytes, bytes)
    }
}
