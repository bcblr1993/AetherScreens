import XCTest
import Combine
@testable import AetherScreensCore

final class PerformanceMetricsTests: XCTestCase {
    @MainActor
    func testObservableNotificationCanReenterFrameRecording() {
        let metrics = PerformanceMetrics()
        var notifications = 0
        let subscription = metrics.objectWillChange.sink {
            XCTAssertTrue(Thread.isMainThread)
            // Metal drawing can run while SwiftUI handles a metrics notification.
            metrics.recordFrame()
            notifications += 1
        }
        metrics.recordLatency(ms: 20)
        XCTAssertGreaterThan(notifications, 0)
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testNetworkThreadPublishesOnMainThread() async {
        let metrics = PerformanceMetrics()
        let notified = expectation(description: "Main-thread metrics publication")
        let subscription = metrics.$latencyMs.dropFirst().sink { value in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(value, 25)
            notified.fulfill()
        }
        DispatchQueue.global().async { metrics.recordLatency(ms: 25) }
        await fulfillment(of: [notified], timeout: 2)
        withExtendedLifetime(subscription) {}
    }

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
