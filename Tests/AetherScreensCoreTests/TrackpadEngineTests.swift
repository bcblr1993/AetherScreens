import XCTest
@testable import AetherScreensCore

final class TrackpadEngineTests: XCTestCase {

    func testCursorInitAndReset() {
        let engine = TrackpadEngine(remoteWidth: 1920, remoteHeight: 1080)
        XCTAssertEqual(engine.cursorX, 960)
        XCTAssertEqual(engine.cursorY, 540)

        engine.handlePanDelta(dx: 100, dy: 100)
        XCTAssertGreaterThan(engine.cursorX, 960)
        XCTAssertGreaterThan(engine.cursorY, 540)

        engine.resetCursor()
        XCTAssertEqual(engine.cursorX, 960)
        XCTAssertEqual(engine.cursorY, 540)
    }

    func testCursorClamping() {
        let engine = TrackpadEngine(remoteWidth: 1000, remoteHeight: 500)
        // Pan way past top-left
        engine.handlePanDelta(dx: -5000, dy: -5000)
        XCTAssertEqual(engine.cursorX, 0)
        XCTAssertEqual(engine.cursorY, 0)

        // Pan way past bottom-right
        engine.handlePanDelta(dx: 10000, dy: 10000)
        XCTAssertEqual(engine.cursorX, 1000)
        XCTAssertEqual(engine.cursorY, 500)
    }

    func testAccelerationCurve() {
        let engine1 = TrackpadEngine(remoteWidth: 2000, remoteHeight: 2000)
        let engine2 = TrackpadEngine(remoteWidth: 2000, remoteHeight: 2000)

        // Small movement (distance 4)
        engine1.handlePanDelta(dx: 4, dy: 0)
        let deltaSmall = engine1.cursorX - 1000

        // Large movement (distance 40)
        engine2.handlePanDelta(dx: 40, dy: 0)
        let deltaLarge = engine2.cursorX - 1000

        // Because of acceleration, large move should be scaled by a higher factor than small move
        let ratio = deltaLarge / deltaSmall
        XCTAssertGreaterThan(ratio, 10.0, "Acceleration should scale fast movements non-linearly")
    }

    func testDirectTouchMapping() {
        let engine = TrackpadEngine(remoteWidth: 1920, remoteHeight: 1080)
        engine.mode = .touch

        let viewSize = CGSize(width: 390, height: 844) // iPhone 14/15 size
        let touchPoint = CGPoint(x: 195, y: 422) // Exact center of iPhone screen

        engine.handleDirectTouch(point: touchPoint, viewSize: viewSize)
        XCTAssertEqual(engine.cursorX, 960, accuracy: 1.0)
        XCTAssertEqual(engine.cursorY, 540, accuracy: 1.0)
    }

    final class EventCollector: @unchecked Sendable {
        private let lock = NSLock()
        var events: [(mask: RFBConstants.ButtonMask, x: UInt16, y: UInt16)] = []
        var masks: [RFBConstants.ButtonMask] = []

        func addEvent(mask: RFBConstants.ButtonMask, x: UInt16, y: UInt16) {
            lock.lock()
            defer { lock.unlock() }
            events.append((mask, x, y))
        }

        func addMask(_ mask: RFBConstants.ButtonMask) {
            lock.lock()
            defer { lock.unlock() }
            masks.append(mask)
        }
    }

    func testTapEmitsPointerEvent() {
        let engine = TrackpadEngine(remoteWidth: 1000, remoteHeight: 1000)
        let collector = EventCollector()

        engine.onPointerEvent = { mask, x, y in
            collector.addEvent(mask: mask, x: x, y: y)
        }

        engine.handleTap()
        XCTAssertFalse(collector.events.isEmpty)
        XCTAssertTrue(collector.events.first?.mask.contains(.left) ?? false)
    }

    func testScrollEvent() {
        let engine = TrackpadEngine(remoteWidth: 1000, remoteHeight: 1000)
        let collector = EventCollector()

        engine.onPointerEvent = { mask, _, _ in
            collector.addMask(mask)
        }

        engine.handleScroll(deltaY: 10) // Scroll Up
        XCTAssertTrue(collector.masks.contains(where: { $0.contains(.scrollUp) }))

        engine.handleScroll(deltaY: -10) // Scroll Down
        XCTAssertTrue(collector.masks.contains(where: { $0.contains(.scrollDown) }))
    }
}
