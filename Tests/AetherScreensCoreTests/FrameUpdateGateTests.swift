import XCTest
@testable import AetherScreensCore

final class FrameUpdateGateTests: XCTestCase {
    func testBurstQueuesOnlyOneTaskAndNextBurstCanSchedule() {
        let gate = FrameUpdateGate(), generation = UUID()
        XCTAssertTrue(gate.enqueue(generation: generation))
        for _ in 0..<999 { XCTAssertFalse(gate.enqueue(generation: generation)) }
        XCTAssertEqual(gate.consume(generation: generation), 1000)
        XCTAssertEqual(gate.consume(generation: generation), 0)
        XCTAssertTrue(gate.enqueue(generation: generation))
        XCTAssertEqual(gate.consume(generation: generation), 1)
    }

    func testOldTaskCannotConsumeReconnectedFrames() {
        let gate = FrameUpdateGate(), old = UUID(), current = UUID()
        XCTAssertTrue(gate.enqueue(generation: old))
        gate.begin(generation: current)
        XCTAssertTrue(gate.enqueue(generation: current))
        XCTAssertFalse(gate.enqueue(generation: old))
        XCTAssertFalse(gate.enqueue(generation: current))
        XCTAssertEqual(gate.consume(generation: old), 0)
        XCTAssertEqual(gate.consume(generation: current), 2)
    }

    func testConcurrentProducersRetainEveryNotification() {
        let gate = FrameUpdateGate(), generation = UUID()
        XCTAssertTrue(gate.enqueue(generation: generation))
        DispatchQueue.concurrentPerform(iterations: 1000) { _ in
            _ = gate.enqueue(generation: generation)
        }
        XCTAssertEqual(gate.consume(generation: generation), 1001)
    }
}
