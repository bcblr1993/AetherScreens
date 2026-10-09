import XCTest
@testable import AetherScreensCore

final class KeyRepeatPressTests: XCTestCase {
    @MainActor
    func testCancelledHoldNeverStartsAndAccessibilityTapStillWorks() async throws {
        let press = KeyRepeatPress()
        var repeats = 0
        var ends = 0
        var taps = 0
        press.pressed(true, repeatAction: { repeats += 1 }, endAction: { ends += 1 })
        press.stop()
        try await Task.sleep(nanoseconds: 500_000_000)
        press.activate { taps += 1 }
        XCTAssertEqual(repeats, 0)
        XCTAssertEqual(ends, 0)
        XCTAssertEqual(taps, 1)
    }

    @MainActor
    func testHoldRepeatsAndStopsWithoutExtraTapOrDuplicateRelease() async throws {
        let press = KeyRepeatPress()
        var repeats = 0
        var ends = 0
        var taps = 0
        let repeated = expectation(description: "Hold repeats")
        press.pressed(true, repeatAction: {
            repeats += 1
            if repeats == 3 { repeated.fulfill() }
        }, endAction: { ends += 1 })
        await fulfillment(of: [repeated], timeout: 2)
        press.stop()
        press.stop()
        press.activate { taps += 1 }
        let stopped = repeats
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(repeats, stopped)
        XCTAssertEqual(ends, 1)
        XCTAssertEqual(taps, 0)
        // VoiceOver activation after the completed hold remains a normal tap.
        press.activate { taps += 1 }
        XCTAssertEqual(taps, 1)
    }
}
