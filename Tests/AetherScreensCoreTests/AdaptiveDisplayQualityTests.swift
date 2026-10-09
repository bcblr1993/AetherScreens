import XCTest
@testable import AetherScreensCore

final class AdaptiveDisplayQualityTests: XCTestCase {
    func testCongestionRequiresThreeSamplesAndCooldown() {
        var policy = AdaptiveDisplayQuality()
        XCTAssertNil(policy.sample(bytes: 20_000, payloadDuration: 0.3, now: 1, foreground: true))
        XCTAssertNil(policy.sample(bytes: 20_000, payloadDuration: 0.3, now: 2, foreground: true))
        XCTAssertEqual(policy.sample(bytes: 20_000, payloadDuration: 0.3, now: 3, foreground: true), .balanced)
        for second in 4..<13 {
            XCTAssertNil(policy.sample(bytes: 20_000, payloadDuration: 0.3, now: Double(second), foreground: true))
        }
        XCTAssertEqual(policy.sample(bytes: 20_000, payloadDuration: 0.3, now: 13, foreground: true), .responsive)
        XCTAssertEqual(policy.level, .responsive)
    }

    func testRecoveryRequiresEightFastTransfers() {
        var policy = AdaptiveDisplayQuality()
        for second in 1...3 { _ = policy.sample(bytes: 20_000, payloadDuration: 0.3, now: Double(second), foreground: true) }
        for second in 6...12 {
            XCTAssertNil(policy.sample(bytes: 20_000, payloadDuration: 0.04, now: Double(second), foreground: true))
        }
        XCTAssertEqual(policy.sample(bytes: 20_000, payloadDuration: 0.04, now: 13, foreground: true), .high)
    }

    func testIdleHiddenSmallAndInvalidSamplesCannotDowngrade() {
        var policy = AdaptiveDisplayQuality()
        for second in 1...20 {
            XCTAssertNil(policy.sample(bytes: 0, payloadDuration: 5, now: Double(second), foreground: true))
            XCTAssertNil(policy.sample(bytes: 100, payloadDuration: 5, now: Double(second), foreground: true))
            XCTAssertNil(policy.sample(bytes: 20_000, payloadDuration: 5, now: Double(second), foreground: false))
            XCTAssertNil(policy.sample(bytes: 20_000, payloadDuration: .nan, now: Double(second), foreground: true))
        }
        XCTAssertEqual(policy.level, .high)
        _ = policy.sample(bytes: 20_000, payloadDuration: 0.3, now: 30, foreground: true)
        XCTAssertNil(policy.sample(bytes: 20_000, payloadDuration: 0.3, now: 30, foreground: true))
        XCTAssertNil(policy.sample(bytes: 20_000, payloadDuration: 0.3, now: 29, foreground: true))
        XCTAssertNil(policy.sample(bytes: 20_000, payloadDuration: 0.3, now: 40, foreground: true), "Long idle gaps reset consecutive evidence")
        policy.reset()
        XCTAssertEqual(policy.level, .high)
    }

    func testQualityHintUsesProtocolValues() {
        XCTAssertEqual(AdaptiveDisplayQuality.Level.high.encodingHint.rawValue, -23)
        XCTAssertEqual(AdaptiveDisplayQuality.Level.balanced.encodingHint.rawValue, -26)
        XCTAssertEqual(AdaptiveDisplayQuality.Level.responsive.encodingHint.rawValue, -29)
    }
}
