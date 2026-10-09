import XCTest
@testable import AetherScreensCore

final class TrackpadEngineTests: XCTestCase {

    func testCompleteChordReleaseIsImmediateAndReentrantSafe() {
        let engine = TrackpadEngine(remoteWidth: 800, remoteHeight: 450)
        let collector = EventCollector()
        engine.beginDrag(button: [.left, .right, .middle])
        engine.onPointerEvent = { mask, x, y in
            collector.addEvent(mask: mask, x: x, y: y)
            if mask.isEmpty { engine.releaseAllButtons() }
        }
        engine.releaseAllButtons()
        engine.releaseAllButtons()
        XCTAssertTrue(engine.activeButtons.isEmpty)
        XCTAssertEqual(collector.events.count, 1)
        XCTAssertEqual(collector.events.first?.mask, [])
        XCTAssertEqual(collector.events.first?.x, 400)
        XCTAssertEqual(collector.events.first?.y, 225)
    }

    func testWireCoordinatesStayInsideLastPixelAcrossButtonsAndScroll() {
        let engine = TrackpadEngine(remoteWidth: 1000, remoteHeight: 500)
        let collector = EventCollector()
        engine.onPointerEvent = { collector.addEvent(mask: $0, x: $1, y: $2) }
        engine.handlePanDelta(dx: 10000, dy: 10000)
        engine.click(button: .right)
        engine.handleScroll(deltaY: 1)
        engine.handleHorizontalScroll(deltaX: 1)
        XCTAssertEqual(collector.events.count, 7)
        XCTAssertTrue(collector.events.allSatisfy { $0.x == 999 && $0.y == 499 })
        engine.remoteWidth = 100000
        engine.remoteHeight = 100000
        engine.resetCursor()
        engine.handlePanDelta(dx: 100000, dy: 100000)
        XCTAssertEqual(collector.events.last?.x, UInt16.max)
        XCTAssertEqual(collector.events.last?.y, UInt16.max)
        engine.remoteWidth = .nan
        engine.remoteHeight = .infinity
        engine.resetCursor()
        engine.click(button: .left)
        XCTAssertEqual(collector.events.last?.x, 0)
        XCTAssertEqual(collector.events.last?.y, 0)
    }

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

    func testHardwarePointerIgnoresFingerModeAndPreservesHeldButtons() {
        let engine = TrackpadEngine(remoteWidth: 1920, remoteHeight: 1080)
        let collector = EventCollector()
        engine.onPointerEvent = { collector.addEvent(mask: $0, x: $1, y: $2) }
        for mode in [TrackpadEngine.Mode.trackpad, .touch] {
            engine.mode = mode
            engine.handleAbsolutePointer(point: CGPoint(x: 100, y: 50), viewSize: CGSize(width: 400, height: 200))
            engine.beginDrag(button: .right)
            engine.handleAbsolutePointer(point: CGPoint(x: 300, y: 150), viewSize: CGSize(width: 400, height: 200))
            XCTAssertEqual(collector.events.last?.mask, .right)
            XCTAssertEqual(collector.events.last?.x, 1440)
            XCTAssertEqual(collector.events.last?.y, 810)
            engine.endDrag(button: .right)
            XCTAssertEqual(collector.events.last?.mask, [])
            let count = collector.events.count
            engine.handleAbsolutePointer(point: .zero, viewSize: .zero)
            XCTAssertEqual(collector.events.count, count, "An empty canvas must not move the pointer")
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
        XCTAssertEqual(collector.events.count, 2, "Press and release must be immediate, without a delayed main-queue timer")
        XCTAssertTrue(collector.events.last?.mask.isEmpty ?? false)
    }

    func testFingerMovementUsesRemotePixelScaleWithoutChangingAcceleration() {
        let normal = TrackpadEngine(remoteWidth: 4000, remoteHeight: 2000)
        let scaled = TrackpadEngine(remoteWidth: 4000, remoteHeight: 2000)
        normal.handlePanDelta(dx: 4, dy: 2)
        scaled.handlePanDelta(dx: 4, dy: 2, coordinateScale: 10)
        XCTAssertEqual(scaled.cursorX - 2000, (normal.cursorX - 2000) * 10, accuracy: 0.001)
        XCTAssertEqual(scaled.cursorY - 1000, (normal.cursorY - 1000) * 10, accuracy: 0.001)
    }

    func testScrollingAndClickingPreserveHeldDragButton() {
        let engine = TrackpadEngine()
        let collector = EventCollector()
        engine.onPointerEvent = { collector.addEvent(mask: $0, x: $1, y: $2) }
        engine.beginDrag(button: .right)
        engine.handleScroll(deltaY: 8)
        engine.handleHorizontalScroll(deltaX: -8)
        engine.click(button: .middle)
        XCTAssertTrue(collector.events.allSatisfy { $0.mask.contains(.right) })
        XCTAssertTrue(collector.events.contains { $0.mask.contains(.scrollRight) })
        engine.endDrag(button: .right)
        XCTAssertTrue(collector.events.last?.mask.isEmpty ?? false)
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
