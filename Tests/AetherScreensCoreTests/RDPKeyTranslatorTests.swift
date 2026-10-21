import XCTest
import RDPKit
@testable import AetherScreensCore

final class RDPKeyTranslatorTests: XCTestCase {
    private let ctrl: UInt32 = 0xffe3
    private let slash: UInt32 = 0x2f

    func testPlainPunctuationTravelsAsUnicodeForLayoutIndependence() {
        var translator = RDPKeyTranslator()
        XCTAssertEqual(translator.events(keySym: slash, down: true), [.unicode(codeUnit: 0x2f, isReleased: false)])
        XCTAssertEqual(translator.events(keySym: slash, down: false), [.unicode(codeUnit: 0x2f, isReleased: true)])
    }

    func testShortcutModifierSendsPunctuationAsScancode() {
        var translator = RDPKeyTranslator()
        _ = translator.events(keySym: ctrl, down: true)
        let slashScancode = RDPKeyboardScancode(code: 0x35)
        XCTAssertEqual(translator.events(keySym: slash, down: true), [.keyboard(scancode: slashScancode, isReleased: false)])
        XCTAssertEqual(translator.events(keySym: slash, down: false), [.keyboard(scancode: slashScancode, isReleased: true)])
        for (keySym, code) in [(UInt32(0x2d), UInt16(0x0c)), (0x3d, 0x0d), (0x5b, 0x1a), (0x3f, 0x35), (0x21, 0x02)] {
            XCTAssertEqual(translator.events(keySym: keySym, down: true), [.keyboard(scancode: RDPKeyboardScancode(code: code), isReleased: false)])
            _ = translator.events(keySym: keySym, down: false)
        }
    }

    func testReleaseMatchesPressKindWhenModifierChangesInBetween() {
        var translator = RDPKeyTranslator()
        _ = translator.events(keySym: ctrl, down: true)
        _ = translator.events(keySym: slash, down: true)
        _ = translator.events(keySym: ctrl, down: false)
        XCTAssertEqual(translator.events(keySym: slash, down: false),
                       [.keyboard(scancode: RDPKeyboardScancode(code: 0x35), isReleased: true)])

        _ = translator.events(keySym: slash, down: true)
        _ = translator.events(keySym: ctrl, down: true)
        XCTAssertEqual(translator.events(keySym: slash, down: false), [.unicode(codeUnit: 0x2f, isReleased: true)])
    }

    func testUnicodeKeySymsAreDeliveredIncludingSupplementaryPlane() {
        var translator = RDPKeyTranslator()
        XCTAssertEqual(translator.events(keySym: 0x0100_4e2d, down: true), [.unicode(codeUnit: 0x4e2d, isReleased: false)]) // 中
        XCTAssertEqual(translator.events(keySym: 0x0100_20ac, down: true), [.unicode(codeUnit: 0x20ac, isReleased: false)]) // €
        XCTAssertEqual(translator.events(keySym: 0x0101_f600, down: true),
                       [.unicode(codeUnit: 0xd83d, isReleased: false), .unicode(codeUnit: 0xde00, isReleased: false)]) // 😀
        XCTAssertEqual(translator.events(keySym: 0xe9, down: true), [.unicode(codeUnit: 0xe9, isReleased: false)]) // é
    }

    func testUnmappedFunctionKeySymsAreDroppedInsteadOfSentAsText() {
        var translator = RDPKeyTranslator()
        XCTAssertEqual(translator.events(keySym: 0xff13, down: true), []) // Pause
        XCTAssertEqual(translator.events(keySym: 0xffca, down: true), []) // F13
        XCTAssertEqual(translator.events(keySym: 0x06c1, down: true), []) // legacy Cyrillic keysym
    }

    func testLockAndKeypadKeysUseScancodes() {
        XCTAssertEqual(RDPClient.mapKeySymToScancode(0xffe5), RDPKeyboardScancode(code: 0x3a))
        XCTAssertEqual(RDPClient.mapKeySymToScancode(0xff8d), RDPKeyboardScancode(code: 0x1c, isExtended: true))
        XCTAssertEqual(RDPClient.mapKeySymToScancode(0xffb5), RDPKeyboardScancode(code: 0x4c))
        XCTAssertEqual(RDPClient.mapKeySymToScancode(0xff67), RDPKeyboardScancode(code: 0x5d, isExtended: true))
    }

    func testLettersKeepScancodesSoCtrlLetterShortcutsWork() {
        var translator = RDPKeyTranslator()
        XCTAssertEqual(translator.events(keySym: 0x63, down: true), [.keyboard(scancode: RDPKeyboardScancode(code: 0x2e), isReleased: false)])
    }
}
