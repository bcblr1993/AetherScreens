import XCTest
@testable import AetherScreensCore

final class HardwareKeyboardTests: XCTestCase {
    func testNavigationAndModifiersDoNotDependOnCharacterStrings() {
        for (usage, expected) in [(0x50, MacKeyMap.arrowLeft), (0x52, MacKeyMap.arrowUp),
                                  (0x4c, MacKeyMap.delete), (0x2a, MacKeyMap.backspace),
                                  (0x28, MacKeyMap.return), (0x58, MacKeyMap.return),
                                  (0x3a, MacKeyMap.f1), (0x45, MacKeyMap.f12),
                                  (0xe3, MacKeyMap.commandLeft), (0xe7, MacKeyMap.commandRight)] {
            XCTAssertEqual(HardwareKeyboard.keySym(usage: usage, characters: ""), expected)
        }
        XCTAssertEqual(HardwareKeyboard.keySym(usage: 4, characters: "a"), 0x61)
        XCTAssertEqual(HardwareKeyboard.keySym(usage: 4, characters: "中"), 0x01004e2d)
        XCTAssertNil(HardwareKeyboard.keySym(usage: 0, characters: ""))
        XCTAssertNil(HardwareKeyboard.keySym(usage: 4, characters: "ab"))
    }

    func testRepeatAndReleaseKeepOriginalKeysymAfterLayoutChange() {
        var state = HardwareKeyboardState()
        XCTAssertEqual(state.begin(usage: 4, characters: "a"), 0x61)
        XCTAssertEqual(state.begin(usage: 4, characters: "A"), 0x61)
        XCTAssertEqual(state.end(usage: 4), 0x61)
        XCTAssertNil(state.end(usage: 4), "Duplicate release must not emit another packet")
        XCTAssertEqual(state.begin(usage: 4, characters: "q"), 0x71)
        XCTAssertEqual(state.end(usage: 4), 0x71)
    }

    func testFocusLossReleasesKeysBeforeModifiersAndResetsState() {
        var state = HardwareKeyboardState()
        XCTAssertEqual(state.begin(usage: 0xe3, characters: ""), MacKeyMap.commandLeft)
        XCTAssertEqual(state.begin(usage: 0xe5, characters: ""), MacKeyMap.shiftRight)
        XCTAssertEqual(state.begin(usage: 6, characters: "c"), 0x63)
        XCTAssertEqual(state.releaseAll(), [0x63, MacKeyMap.commandLeft, MacKeyMap.shiftRight])
        XCTAssertTrue(state.releaseAll().isEmpty)
        XCTAssertNil(state.end(usage: 0xe3))
        XCTAssertEqual(state.begin(usage: 6, characters: "C"), 0x43)
    }
}
