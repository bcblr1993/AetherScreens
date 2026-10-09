import XCTest
@testable import AetherScreensCore

final class ThumbnailSnapshotSchedulerTests: XCTestCase {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Int] = []
        func record(_ value: Int) {
            lock.lock(); defer { lock.unlock() }
            values.append(value)
        }
        var recorded: [Int] {
            lock.lock(); defer { lock.unlock() }
            return values
        }
    }

    func testFirstFrameAndTimeCadenceAreIndependentOfFrameRate() {
        var cadence = ThumbnailSnapshotCadence()
        XCTAssertTrue(cadence.shouldCapture(at: 10))
        for frame in 1..<600 {
            XCTAssertFalse(cadence.shouldCapture(at: 10 + Double(frame) / 120))
        }
        XCTAssertTrue(cadence.shouldCapture(at: 15))
        XCTAssertFalse(cadence.shouldCapture(at: 15))
        XCTAssertTrue(cadence.shouldCapture(at: 100), "A quiet desktop captures on its next changed frame")
        cadence = ThumbnailSnapshotCadence()
        XCTAssertTrue(cadence.shouldCapture(at: 100), "A replacement session captures its first frame")
    }

    func testInvalidAndRegressingTimesDoNotAdvanceCadence() {
        var cadence = ThumbnailSnapshotCadence()
        for invalid in [Double.nan, .infinity, -1] {
            XCTAssertFalse(cadence.shouldCapture(at: invalid))
        }
        XCTAssertTrue(cadence.shouldCapture(at: 10))
        XCTAssertFalse(cadence.shouldCapture(at: 9))
        XCTAssertTrue(cadence.shouldCapture(at: 15))
    }

    func testQueuedBurstRetainsOnlyLatestSnapshot() {
        let queue = DispatchQueue(label: "thumbnail-snapshot-test")
        queue.suspend()
        let scheduler = ThumbnailSnapshotScheduler(queue: queue)
        let recorder = Recorder()
        let done = expectation(description: "latest snapshot")
        for index in 0..<100 {
            scheduler.schedule {
                recorder.record(index)
                if index == 99 { done.fulfill() }
            }
        }
        queue.resume()
        wait(for: [done], timeout: 5)
        XCTAssertEqual(recorder.recorded, [99])
    }

    func testActiveSnapshotFinishesAndFinalSnapshotIsNotLost() {
        let queue = DispatchQueue(label: "thumbnail-active-snapshot-test")
        let scheduler = ThumbnailSnapshotScheduler(queue: queue)
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let recorder = Recorder()
        let final = expectation(description: "disconnect snapshot")
        scheduler.schedule {
            started.signal()
            guard release.wait(timeout: .now() + 5) == .success else { return }
            recorder.record(0)
        }
        XCTAssertEqual(started.wait(timeout: .now() + 5), .success)
        for index in 1..<100 {
            scheduler.schedule { recorder.record(index) }
        }
        scheduler.schedule {
            recorder.record(100)
            final.fulfill()
        }
        release.signal()
        wait(for: [final], timeout: 5)
        XCTAssertEqual(recorder.recorded, [0, 100])
        queue.sync {} // Ensure the worker has actually returned to idle.
        // A completed drain must also accept work from a subsequent session.
        let resumed = expectation(description: "resumed session")
        scheduler.schedule { recorder.record(101); resumed.fulfill() }
        wait(for: [resumed], timeout: 5)
        XCTAssertEqual(recorder.recorded, [0, 100, 101])
    }
}
