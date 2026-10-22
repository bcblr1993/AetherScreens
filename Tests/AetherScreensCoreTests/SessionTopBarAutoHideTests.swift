import XCTest
@testable import AetherScreensCore

final class SessionTopBarAutoHideTests: XCTestCase {
    private func fire(_ state: inout SessionTopBarAutoHide) {
        guard let timer = state.pendingTimer else { return XCTFail("No pending timer") }
        state.timerFired(timer, generation: state.timerGeneration)
    }

    private func hiddenState() -> SessionTopBarAutoHide {
        var state = SessionTopBarAutoHide()
        state.setPinned(false)
        fire(&state)
        return state
    }

    func testPinnedBarStaysVisibleWithoutTimers() {
        var state = SessionTopBarAutoHide()
        state.pointerMoved(toY: 400)
        XCTAssertTrue(state.isRevealed)
        XCTAssertNil(state.pendingTimer)
    }

    func testUnpinningHidesAfterDelayUnlessPointerIsOnBar() {
        var state = SessionTopBarAutoHide()
        state.setPinned(false)
        XCTAssertEqual(state.pendingTimer, .hide)
        fire(&state)
        XCTAssertFalse(state.isRevealed)

        var onBar = SessionTopBarAutoHide()
        onBar.pointerMoved(toY: 30)
        onBar.setPinned(false)
        XCTAssertNil(onBar.pendingTimer)
        XCTAssertTrue(onBar.isRevealed)
    }

    func testPointerBelowRevealZoneNeverRevealsHiddenBar() {
        var state = hiddenState()
        state.pointerMoved(toY: SessionTopBarAutoHide.revealZone + 1)
        XCTAssertNil(state.pendingTimer)
        XCTAssertFalse(state.isRevealed)
    }

    func testDwellingAtTopEdgeRevealsAndLeavingCancels() {
        var state = hiddenState()
        state.pointerMoved(toY: 2)
        XCTAssertEqual(state.pendingTimer, .reveal)
        let generation = state.timerGeneration
        state.pointerMoved(toY: 4)
        XCTAssertEqual(state.timerGeneration, generation, "Moving within the zone must not restart the dwell")

        state.pointerMoved(toY: 200)
        XCTAssertNil(state.pendingTimer)
        state.timerFired(.reveal, generation: generation)
        XCTAssertFalse(state.isRevealed, "A cancelled dwell must not reveal the bar")

        state.pointerMoved(toY: 0)
        fire(&state)
        XCTAssertTrue(state.isRevealed)
    }

    func testRevealedBarHidesOnlyAfterPointerLeavesBarArea() {
        var state = hiddenState()
        state.pointerMoved(toY: 0)
        fire(&state)
        state.pointerMoved(toY: SessionTopBarAutoHide.retainZone)
        XCTAssertNil(state.pendingTimer)

        state.pointerMoved(toY: 300)
        XCTAssertEqual(state.pendingTimer, .hide)
        let generation = state.timerGeneration
        state.pointerMoved(toY: 320)
        XCTAssertEqual(state.timerGeneration, generation, "Continuous motion must not defer hiding forever")

        state.pointerMoved(toY: nil)
        fire(&state)
        XCTAssertFalse(state.isRevealed)
    }

    func testPinningCancelsHideAndRevealsImmediately() {
        var state = hiddenState()
        state.setPinned(true)
        XCTAssertTrue(state.isRevealed)
        XCTAssertNil(state.pendingTimer)

        state.setPinned(false)
        let generation = state.timerGeneration
        state.setPinned(true)
        state.timerFired(.hide, generation: generation)
        XCTAssertTrue(state.isRevealed, "A hide timer from before pinning must be ignored")
    }

    func testMotionWithinOneZoneLeavesStateUnchanged() {
        var state = hiddenState()
        state.pointerMoved(toY: 300)
        let before = state
        state.pointerMoved(toY: 420)
        XCTAssertEqual(state, before)
    }
}
