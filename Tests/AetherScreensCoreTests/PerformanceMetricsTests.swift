import XCTest
@testable import AetherScreensCore

final class PerformanceMetricsTests: XCTestCase {

    func testInitialState() {
        let metrics = PerformanceMetrics()
        XCTAssertEqual(metrics.currentFPS, 0.0)
        XCTAssertEqual(metrics.latencyMs, 0.0)
        XCTAssertTrue(metrics.isOptimal)
    }

    func testLatencyRecording() {
        let metrics = PerformanceMetrics()
        metrics.recordLatency(ms: 30.0)
        XCTAssertEqual(metrics.latencyMs, 30.0)
        XCTAssertTrue(metrics.isOptimal)

        metrics.recordLatency(ms: 100.0)
        // Moving average: 30 * 0.7 + 100 * 0.3 = 51.0
        XCTAssertEqual(metrics.latencyMs, 51.0, accuracy: 0.1)
        XCTAssertTrue(metrics.isOptimal)

        // Latency climbs past 60ms threshold
        metrics.recordLatency(ms: 120.0)
        XCTAssertFalse(metrics.isOptimal)
    }

    func testFrameAndBandwidthRecording() {
        let metrics = PerformanceMetrics()
        metrics.recordFrame()
        metrics.recordBytesReceived(1024 * 100) // 100 KB
        XCTAssertNotNil(metrics.currentFPS)
    }
}
