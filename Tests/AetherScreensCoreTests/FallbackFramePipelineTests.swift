import XCTest
@testable import AetherScreensCore

final class FallbackFramePipelineTests: XCTestCase {
    private final class Reads: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Int] = []
        func add(_ width: Int) { lock.lock(); values.append(width); lock.unlock() }
        var widths: [Int] { lock.lock(); defer { lock.unlock() }; return values }
    }

    func testSlowCopyReplacesPendingFramesAndPublishesOnMain() {
        let started = expectation(description: "Background copy started")
        let latest = expectation(description: "Latest image published")
        let release = DispatchSemaphore(value: 0), reads = Reads()
        defer { release.signal() }
        let pipeline = FallbackFramePipeline { framebuffer in
            XCTAssertFalse(Thread.isMainThread)
            reads.add(framebuffer.width)
            if framebuffer.width == 1 {
                started.fulfill()
                XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
            }
            return framebuffer.makeCGImage()
        }
        let generation = UUID()
        let publish: @Sendable (CGImage, UUID) -> Void = { image, received in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(received, generation)
            if image.width == 3 { latest.fulfill() }
        }
        pipeline.submit(framebuffer: Framebuffer(width: 1, height: 1), generation: generation, publish: publish)
        wait(for: [started], timeout: 3)
        pipeline.submit(framebuffer: Framebuffer(width: 2, height: 1), generation: generation, publish: publish)
        pipeline.submit(framebuffer: Framebuffer(width: 3, height: 1), generation: generation, publish: publish)
        release.signal()
        wait(for: [latest], timeout: 3)
        XCTAssertEqual(reads.widths, [1, 3])
    }

    func testReconnectDiscardsInFlightOldImageAndRejectsOldRequests() {
        let started = expectation(description: "Old copy started")
        let current = expectation(description: "Current image published")
        let release = DispatchSemaphore(value: 0), reads = Reads()
        defer { release.signal() }
        let pipeline = FallbackFramePipeline { framebuffer in
            reads.add(framebuffer.width)
            if framebuffer.width == 1 {
                started.fulfill()
                XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
            }
            return framebuffer.makeCGImage()
        }
        let old = UUID(), new = UUID()
        pipeline.submit(framebuffer: Framebuffer(width: 1, height: 1), generation: old) { _, _ in
            XCTFail("Old image must not reach the reconnected session")
        }
        wait(for: [started], timeout: 3)
        pipeline.begin(generation: new)
        pipeline.submit(framebuffer: Framebuffer(width: 2, height: 1), generation: old) { _, _ in
            XCTFail("Old request must be rejected")
        }
        pipeline.submit(framebuffer: Framebuffer(width: 3, height: 1), generation: new) { image, generation in
            XCTAssertEqual(image.width, 3); XCTAssertEqual(generation, new)
            current.fulfill()
        }
        release.signal()
        wait(for: [current], timeout: 3)
        XCTAssertEqual(reads.widths, [1, 3])
    }
}
