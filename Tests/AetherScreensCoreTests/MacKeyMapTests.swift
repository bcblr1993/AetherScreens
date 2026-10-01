import XCTest
@testable import AetherScreensCore

final class MacKeyMapTests: XCTestCase {

    func testASCIICharacterMapping() {
        XCTAssertEqual(MacKeyMap.keySym(for: "a"), 0x0061)
        XCTAssertEqual(MacKeyMap.keySym(for: "Z"), 0x005A)
        XCTAssertEqual(MacKeyMap.keySym(for: "1"), 0x0031)
        XCTAssertEqual(MacKeyMap.keySym(for: " "), 0x0020)
    }

    func testUnicodeCharacterMapping() {
        XCTAssertEqual(MacKeyMap.keySym(for: "中"), 0x01004E2D)
        XCTAssertEqual(MacKeyMap.keySym(for: "é"), 0xE9)
        XCTAssertEqual(MacKeyMap.keySym(for: "😀"), 0x0101F600)
        XCTAssertNil(MacKeyMap.keySym(for: "👨‍👩‍👧"))
    }

    func testModifiersValues() {
        XCTAssertEqual(MacKeyMap.shiftLeft, 0xFFE1)
        XCTAssertEqual(MacKeyMap.controlLeft, 0xFFE3)
        XCTAssertEqual(MacKeyMap.optionLeft, 0xFFE9)
        XCTAssertEqual(MacKeyMap.commandLeft, 0xFFEB)
        XCTAssertEqual(MacKeyMap.return, 0xFF0D)
        XCTAssertEqual(MacKeyMap.escape, 0xFF1B)
    }

    func testMacShortcutsIntegrity() {
        for shortcut in MacKeyMap.MacShortcut.allCases {
            let sequence = shortcut.keySequence
            XCTAssertFalse(sequence.isEmpty, "\(shortcut.rawValue) sequence must not be empty")

            // Every key that goes down must also go up
            let downKeys = sequence.filter { $0.down }.map { $0.key }
            let upKeys = sequence.filter { !$0.down }.map { $0.key }
            XCTAssertEqual(downKeys.sorted(), upKeys.sorted(), "\(shortcut.rawValue) down and up keys must match")
        }
    }
}
