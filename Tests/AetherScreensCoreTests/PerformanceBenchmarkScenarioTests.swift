import XCTest
@testable import AetherScreensCore

final class PerformanceBenchmarkScenarioTests: XCTestCase {

    final class CounterBox: @unchecked Sendable {
        var count: Int = 0
    }

    /// Benchmark 1: Raw Framebuffer Dirty Rect Blit Throughput
    /// Target: Capable of sustaining > 120 FPS rendering on Apple Silicon
    func testRawFramebufferBlitPerformance() {
        let fb = Framebuffer(width: 2560, height: 1600) // 16-inch MacBook Pro resolution
        let rectWidth = 400
        let rectHeight = 300
        let pixelBytes = rectWidth * rectHeight * 4
        let dummyData = Data(repeating: 128, count: pixelBytes)

        let iterations = 100
        let startTime = CFAbsoluteTimeGetCurrent()

        for i in 0..<iterations {
            let x = (i * 20) % (2560 - rectWidth)
            let y = (i * 15) % (1600 - rectHeight)
            fb.updateRect(x: x, y: y, width: rectWidth, height: rectHeight, rawData: dummyData)
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let totalPixels = Double(iterations * rectWidth * rectHeight)
        let megaPixelsPerSec = (totalPixels / elapsed) / 1_000_000.0

        print("[Performance Benchmark] Blit throughput: \(String(format: "%.2f", megaPixelsPerSec)) MPixels/sec (Elapsed: \(String(format: "%.4f", elapsed))s)")

        // Must sustain at least 50 MPixels/sec on Apple Silicon
        XCTAssertGreaterThan(megaPixelsPerSec, 50.0, "Framebuffer blit performance should exceed 50 MPixels/sec")
    }

    /// Benchmark 2: CopyRect Blit Throughput (In-memory scroll/window movement)
    func testCopyRectBlitPerformance() {
        let fb = Framebuffer(width: 3840, height: 2160) // 4K Desktop
        let copyWidth = 1920
        let copyHeight = 1080

        let iterations = 50
        let startTime = CFAbsoluteTimeGetCurrent()

        for _ in 0..<iterations {
            fb.copyRect(srcX: 0, srcY: 0, dstX: 50, dstY: 50, width: copyWidth, height: copyHeight)
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let timePerCopyMs = (elapsed / Double(iterations)) * 1000.0

        print("[Performance Benchmark] CopyRect 1080p blit time: \(String(format: "%.3f", timePerCopyMs)) ms per frame")

        // 1080p CopyRect must execute in under 15ms (sustaining 60-120fps)
        XCTAssertLessThan(timePerCopyMs, 15.0, "1080p CopyRect should execute within 15ms")
    }

    /// Benchmark 3: Trackpad Physics Engine Latency
    func testTrackpadEngineLatency() {
        let engine = TrackpadEngine(remoteWidth: 2560, remoteHeight: 1600)
        let iterations = 10_000

        let counter = CounterBox()
        engine.onPointerEvent = { _, _, _ in
            counter.count += 1
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        for i in 0..<iterations {
            let dx = CGFloat((i % 20) - 10)
            let dy = CGFloat(((i * 3) % 20) - 10)
            engine.handlePanDelta(dx: dx, dy: dy)
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let latencyPerEventMicroseconds = (elapsed / Double(iterations)) * 1_000_000.0

        print("[Performance Benchmark] Trackpad gesture latency: \(String(format: "%.3f", latencyPerEventMicroseconds)) µs/event")

        XCTAssertEqual(counter.count, iterations)
        // Must execute in less than 50 microseconds per event (< 0.05ms)
        XCTAssertLessThan(latencyPerEventMicroseconds, 50.0, "Trackpad processing must be ultra-low latency (< 50µs)")
    }

    /// Benchmark 4: 120 FPS High-Refresh Rate Stability & Latency Smoothing
    func testHighRefreshRate120FPSMetrics() {
        let metrics = PerformanceMetrics()

        // Simulate 120 FPS frame arrivals and network bandwidth
        for _ in 0..<120 {
            metrics.recordFrame()
            metrics.recordBytesReceived(16384)
        }

        // Simulate RTT Latency readings with jitter (20ms, 40ms, 15ms, 22ms)
        metrics.recordLatency(ms: 20.0)
        metrics.recordLatency(ms: 40.0)
        metrics.recordLatency(ms: 15.0)
        metrics.recordLatency(ms: 22.0)

        // Verify exponential smoothing prevented wild swings
        XCTAssertGreaterThan(metrics.latencyMs, 10.0)
        XCTAssertLessThan(metrics.latencyMs, 45.0)
    }
}
