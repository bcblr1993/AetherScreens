import XCTest
@testable import AetherScreensCore

final class TrackpadEngineTests: XCTestCase {
    func testCursorSpeedScalesRelativeMotionWithoutChangingAbsoluteInput() {
        let slow = TrackpadEngine(remoteWidth: 1000, remoteHeight: 1000)
        let fast = TrackpadEngine(remoteWidth: 1000, remoteHeight: 1000)
        fast.cursorSpeedMultiplier = 2
        slow.handlePanDelta(dx: 5, dy: -5, coordinateScale: 2)
        fast.handlePanDelta(dx: 5, dy: -5, coordinateScale: 2)
        XCTAssertEqual(fast.cursorX - 500, (slow.cursorX - 500) * 2, accuracy: 0.001)
        XCTAssertEqual(fast.cursorY - 500, (slow.cursorY - 500) * 2, accuracy: 0.001)
        for engine in [slow, fast] {
            engine.handleAbsolutePointer(point: CGPoint(x: 25, y: 75), viewSize: CGSize(width: 100, height: 100), buttons: [], source: .mouse)
        }
        XCTAssertEqual(slow.cursorX, fast.cursorX)
        XCTAssertEqual(slow.cursorY, fast.cursorY)
        let before = fast.cursorX
        fast.handlePanDelta(dx: .nan, dy: 0)
        XCTAssertEqual(fast.cursorX, before)
        XCTAssertEqual(RemoteDevice.validatedCursorSpeed(.nan), 1)
        XCTAssertEqual(RemoteDevice.validatedCursorSpeed(-1), 0.25)
        XCTAssertEqual(RemoteDevice.validatedCursorSpeed(100), 2)
    }

    func testAbsoluteDevicesMapDesktopCoordinatesInEitherFingerModeAndRejectInvalidGeometry() {
        for mode in [TrackpadEngine.Mode.trackpad, .touch] {
            let engine = TrackpadEngine(remoteWidth: 1920, remoteHeight: 1080)
            engine.mode = mode
            let events = EventCollector()
            engine.onPointerEvent = { events.addEvent(mask: $0, x: $1, y: $2) }
            engine.handleAbsolutePointer(point: CGPoint(x: 100, y: 50), viewSize: CGSize(width: 400, height: 200), buttons: [.right, .middle], source: .mouse)
            XCTAssertEqual(events.events.last?.x, 480)
            XCTAssertEqual(events.events.last?.y, 270)
            XCTAssertEqual(events.events.last?.mask, [.right, .middle])
            engine.handleAbsolutePointer(point: CGPoint(x: 800, y: -50), viewSize: CGSize(width: 400, height: 200), buttons: .left, source: .pencil)
            XCTAssertEqual(events.events.last?.x, 1919)
            XCTAssertEqual(events.events.last?.y, 0)
            let count = events.events.count
            engine.handleAbsolutePointer(point: CGPoint(x: CGFloat.nan, y: 0), viewSize: CGSize(width: 400, height: 200), buttons: [], source: .mouse)
            engine.handleAbsolutePointer(point: .zero, viewSize: .zero, buttons: [], source: .pencil)
            XCTAssertEqual(events.events.count, count)
            XCTAssertEqual(engine.activeButtons, [.left, .right, .middle])
        }
    }

    func testFingerMouseAndPencilOwnButtonsIndependentlyIncludingScroll() {
        let engine = TrackpadEngine()
        let events = EventCollector()
        engine.onPointerEvent = { events.addEvent(mask: $0, x: $1, y: $2) }
        engine.beginDrag(button: .left)
        engine.handleAbsolutePointer(point: .zero, viewSize: CGSize(width: 100, height: 100), buttons: [.left, .right], source: .mouse)
        engine.handleAbsolutePointer(point: .zero, viewSize: CGSize(width: 100, height: 100), buttons: .left, source: .pencil)
        engine.endDrag(button: .left)
        XCTAssertEqual(engine.activeButtons, [.left, .right])
        engine.releaseAbsolutePointer(.mouse)
        XCTAssertEqual(engine.activeButtons, .left, "Releasing the mouse must preserve the Pencil's held left button")
        engine.handleHorizontalScroll(deltaX: 8)
        XCTAssertEqual(events.events.suffix(2).map(\.mask), [[.left, .scrollLeft], .left])
        engine.releaseAbsolutePointer(.pencil)
        XCTAssertTrue(engine.activeButtons.isEmpty)
        XCTAssertTrue(events.events.last?.mask.isEmpty == true)
    }

    func testReleaseAllClearsEveryDeviceAndWheelBitsCannotBecomeHeldButtons() {
        let engine = TrackpadEngine()
        engine.beginDrag(button: .middle)
        engine.handleAbsolutePointer(point: .zero, viewSize: CGSize(width: 100, height: 100), buttons: [.right, .scrollUp], source: .mouse)
        engine.handleAbsolutePointer(point: .zero, viewSize: CGSize(width: 100, height: 100), buttons: .left, source: .pencil)
        XCTAssertEqual(engine.activeButtons, [.left, .right, .middle])
        engine.releaseAllButtons()
        XCTAssertTrue(engine.activeButtons.isEmpty)
        XCTAssertTrue(engine.absolutePointerButtons(for: .mouse).isEmpty)
        XCTAssertTrue(engine.absolutePointerButtons(for: .pencil).isEmpty)
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

    func testScrollAccumulatorRetainsFractionsAndBalancesBothAxes() {
        var scroll = NativeScrollAccumulator()
        for _ in 0..<7 { XCTAssertTrue(scroll.consume(dx: 1, dy: -1, pointsPerTick: 8).isEmpty) }
        XCTAssertEqual(scroll.consume(dx: 1, dy: -1, pointsPerTick: 8), [.scrollDown, .scrollLeft])
        XCTAssertEqual(scroll.consume(dx: -16, dy: 24, pointsPerTick: 8), [.scrollUp, .scrollUp, .scrollUp, .scrollRight, .scrollRight])
        XCTAssertTrue(scroll.consume(dx: 4, dy: 0, pointsPerTick: 8).isEmpty)
        XCTAssertTrue(scroll.consume(dx: -4, dy: 0, pointsPerTick: 8).isEmpty)
    }

    func testScrollAccumulatorRejectsInvalidSamplesAndBoundsLargeSamplesWithoutBacklog() {
        var scroll = NativeScrollAccumulator()
        XCTAssertTrue(scroll.consume(dx: 4, dy: 0, pointsPerTick: 8).isEmpty)
        for invalid: CGFloat in [.nan, .infinity, -.infinity] {
            XCTAssertTrue(scroll.consume(dx: invalid, dy: 8, pointsPerTick: 8).isEmpty)
            XCTAssertTrue(scroll.consume(dx: 8, dy: invalid, pointsPerTick: 8).isEmpty)
            XCTAssertTrue(scroll.consume(dx: 8, dy: 8, pointsPerTick: invalid).isEmpty)
        }
        XCTAssertTrue(scroll.consume(dx: 8, dy: 8, pointsPerTick: 0).isEmpty)
        XCTAssertEqual(scroll.consume(dx: 4, dy: 0, pointsPerTick: 8), [.scrollLeft], "Invalid samples must preserve normal fractional motion")
        let ticks = scroll.consume(dx: .greatestFiniteMagnitude, dy: -.greatestFiniteMagnitude, pointsPerTick: 8)
        XCTAssertEqual(ticks.count, 128)
        XCTAssertEqual(ticks.filter { $0 == .scrollLeft }.count, 64)
        XCTAssertEqual(ticks.filter { $0 == .scrollDown }.count, 64)
        XCTAssertTrue(scroll.consume(dx: 0, dy: 0, pointsPerTick: 8).isEmpty, "Oversized events must not defer wheel floods into later input")
    }

    func testInvalidScrollDoesNotEmitOrReleaseHeldButtons() {
        let engine = TrackpadEngine()
        let collector = EventCollector()
        engine.onPointerEvent = { collector.addEvent(mask: $0, x: $1, y: $2) }
        engine.beginDrag(button: .right)
        let before = collector.events.count
        for invalid: CGFloat in [.nan, .infinity, -.infinity] {
            engine.handleScroll(deltaY: invalid)
            engine.handleHorizontalScroll(deltaX: invalid)
        }
        XCTAssertEqual(collector.events.count, before)
        XCTAssertEqual(engine.activeButtons, .right)
        engine.handleScroll(deltaY: -8)
        XCTAssertEqual(collector.events.suffix(2).map(\.mask), [[.right, .scrollDown], .right])
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
