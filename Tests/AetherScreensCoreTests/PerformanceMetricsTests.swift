import XCTest
import Combine
@testable import AetherScreensCore

final class PerformanceMetricsTests: XCTestCase {
    @MainActor
    func testZeroLatencyRemainsAValidSampleAndResetStartsANewWindow() {
        let metrics = PerformanceMetrics()
        XCTAssertFalse(metrics.hasLatencyMeasurements)
        metrics.recordLatency(ms: 0)
        XCTAssertTrue(metrics.hasLatencyMeasurements)
        metrics.recordLatency(ms: 100)
        XCTAssertEqual(metrics.latencyMs, 30)
        XCTAssertTrue(metrics.isOptimal)
        metrics.reset()
        XCTAssertFalse(metrics.hasLatencyMeasurements)
        metrics.recordLatency(ms: 100)
        XCTAssertEqual(metrics.latencyMs, 100)
        XCTAssertFalse(metrics.isOptimal)
    }

    @MainActor
    func testSubscriberNewerLatencySurvivesOuterPublishedSetter() {
        let metrics = PerformanceMetrics()
        var recorded = false
        let subscription = metrics.objectWillChange.sink {
            guard !recorded else { return }
            recorded = true
            metrics.recordLatency(ms: 0)
        }
        metrics.recordLatency(ms: 100)
        XCTAssertEqual(metrics.latencyMs, 70)
        XCTAssertFalse(metrics.isOptimal)
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testSubscriberResetSurvivesOuterPublishedSetter() {
        let metrics = PerformanceMetrics()
        var reset = false
        let subscription = metrics.objectWillChange.sink {
            guard !reset else { return }
            reset = true
            MainActor.assumeIsolated { metrics.reset() }
        }
        metrics.recordLatency(ms: 100)
        XCTAssertEqual(metrics.latencyMs, 0)
        XCTAssertTrue(metrics.isOptimal)
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testQueuedOlderLatencyCannotReplaceNewerMainThreadSample() async {
        let metrics = PerformanceMetrics()
        let queued = DispatchSemaphore(value: 0)
        DispatchQueue(label: "metrics-old-latency").async {
            metrics.recordLatency(ms: 100)
            queued.signal()
        }
        XCTAssertEqual(queued.wait(timeout: .now() + 2), .success)
        metrics.recordLatency(ms: 0)
        let latest = metrics.latencyMs
        let drained = expectation(description: "Old latency publication drained")
        DispatchQueue.main.async { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 2)
        XCTAssertEqual(latest, 70)
        XCTAssertEqual(metrics.latencyMs, latest)
        XCTAssertFalse(metrics.isOptimal)
    }

    @MainActor
    func testIdenticalMetricsDoNotRepublishUnchangedUIValues() {
        let metrics = PerformanceMetrics()
        metrics.recordLatency(ms: 20)
        var notifications = 0
        let subscription = metrics.objectWillChange.sink { notifications += 1 }
        for _ in 0..<100 { metrics.recordLatency(ms: 20) }
        XCTAssertEqual(notifications, 0)
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testObservableNotificationCanReenterFrameRecording() {
        let metrics = PerformanceMetrics()
        var notifications = 0
        let subscription = metrics.objectWillChange.sink {
            XCTAssertTrue(Thread.isMainThread)
            // Metal drawing can run while SwiftUI handles a metrics notification.
            metrics.recordPresentedFrame(at: 1, generation: metrics.measurementGeneration)
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

    @MainActor
    func testResetRejectsQueuedPublicationsAndOldDrawablePresentations() async {
        let clock = MetricsTestClock()
        let metrics = PerformanceMetrics(clock: { clock.now })
        let oldGeneration = metrics.measurementGeneration
        clock.now = 2
        let queued = DispatchSemaphore(value: 0)
        DispatchQueue(label: "metrics-old-session").async {
            metrics.recordLatency(ms: 120)
            metrics.recordBytesReceived(4096)
            metrics.recordPresentedFrame(at: 2, generation: oldGeneration)
            queued.signal()
        }
        XCTAssertEqual(queued.wait(timeout: .now() + 2), .success)
        metrics.reset()
        metrics.recordPresentedFrame(at: 3, generation: oldGeneration)
        let drained = expectation(description: "Previous main-thread publications drained")
        DispatchQueue.main.async { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 2)
        XCTAssertEqual(metrics.currentFPS, 0)
        XCTAssertEqual(metrics.latencyMs, 0)
        XCTAssertEqual(metrics.bandwidthKbps, 0)
        XCTAssertEqual(metrics.acceptedPresentationCount, 0)
        XCTAssertFalse(metrics.hasPresentationMeasurements)
        XCTAssertTrue(metrics.isOptimal)
        metrics.recordLatency(ms: 10)
        clock.now = 4
        metrics.recordPresentedFrame(at: 4, generation: metrics.measurementGeneration)
        XCTAssertEqual(metrics.latencyMs, 10)
        XCTAssertEqual(metrics.acceptedPresentationCount, 1)
        XCTAssertGreaterThan(metrics.currentFPS, 0)
    }

    func testDroppedAndInvalidPresentationTimesDoNotInflateFPS() {
        let clock = MetricsTestClock()
        let metrics = PerformanceMetrics(clock: { clock.now })
        let generation = metrics.measurementGeneration
        clock.now = 2
        for invalid in [0, -1, Double.nan, .infinity] {
            metrics.recordPresentedFrame(at: invalid, generation: generation)
        }
        XCTAssertEqual(metrics.currentFPS, 0)
        XCTAssertEqual(metrics.acceptedPresentationCount, 0)
        XCTAssertFalse(metrics.hasPresentationMeasurements)
        metrics.recordPresentedFrame(at: 2, generation: generation)
        XCTAssertEqual(metrics.acceptedPresentationCount, 1)
        XCTAssertTrue(metrics.hasPresentationMeasurements)
        XCTAssertEqual(metrics.currentFPS, 0.5)
    }

    @MainActor
    func testSamplingPublishesShortBurstThenIdleRates() {
        let clock = MetricsTestClock()
        let metrics = PerformanceMetrics(clock: { clock.now })
        let generation = metrics.measurementGeneration
        clock.now = 0.25
        metrics.recordPresentedFrame(at: 0.25, generation: generation)
        metrics.recordPresentedFrame(at: 0.25, generation: generation)
        metrics.recordBytesReceived(2048)
        metrics.recordLatency(ms: 20)
        clock.now = 1
        metrics.sampleRates()
        XCTAssertEqual(metrics.currentFPS, 2)
        XCTAssertEqual(metrics.bandwidthKbps, 16)
        clock.now = 2
        metrics.sampleRates()
        XCTAssertEqual(metrics.currentFPS, 0)
        XCTAssertEqual(metrics.bandwidthKbps, 0)
        XCTAssertEqual(metrics.acceptedPresentationCount, 2)
        XCTAssertEqual(metrics.latencyMs, 20)
    }

    @MainActor
    func testSubsecondSamplingPreservesPendingMeasurements() {
        let clock = MetricsTestClock()
        let metrics = PerformanceMetrics(clock: { clock.now })
        clock.now = 0.2
        metrics.recordFrame()
        metrics.recordBytesReceived(1024)
        clock.now = 0.8
        metrics.sampleRates()
        XCTAssertEqual(metrics.currentFPS, 0)
        XCTAssertEqual(metrics.bandwidthKbps, 0)
        clock.now = 1
        metrics.sampleRates()
        XCTAssertEqual(metrics.currentFPS, 1)
        XCTAssertEqual(metrics.bandwidthKbps, 8)
    }

    @MainActor
    func testNewerIdleSampleRejectsOlderSameSessionRatePublications() async {
        let clock = MetricsTestClock()
        let metrics = PerformanceMetrics(clock: { clock.now })
        clock.now = 1
        let queued = DispatchSemaphore(value: 0)
        DispatchQueue(label: "metrics-earlier-window").async {
            metrics.recordFrame()
            metrics.recordBytesReceived(1024)
            queued.signal()
        }
        XCTAssertEqual(queued.wait(timeout: .now() + 2), .success)
        clock.now = 2
        metrics.sampleRates()
        let drained = expectation(description: "Earlier rate publications drained")
        DispatchQueue.main.async { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 2)
        XCTAssertEqual(metrics.currentFPS, 0)
        XCTAssertEqual(metrics.bandwidthKbps, 0)
    }

    @MainActor
    func testResetRejectsQueuedRateSample() async {
        let clock = MetricsTestClock()
        let metrics = PerformanceMetrics(clock: { clock.now })
        clock.now = 0.2
        metrics.recordFrame()
        metrics.recordBytesReceived(1024)
        clock.now = 1
        let queued = DispatchSemaphore(value: 0)
        DispatchQueue(label: "metrics-old-sample").async { metrics.sampleRates(); queued.signal() }
        XCTAssertEqual(queued.wait(timeout: .now() + 2), .success)
        metrics.reset()
        metrics.recordLatency(ms: 15)
        let drained = expectation(description: "Old sample drained")
        DispatchQueue.main.async { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 2)
        XCTAssertEqual(metrics.currentFPS, 0)
        XCTAssertEqual(metrics.bandwidthKbps, 0)
        XCTAssertEqual(metrics.latencyMs, 15)
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

private final class MetricsTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 0
    var now: TimeInterval {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); value = newValue; lock.unlock() }
    }
}
