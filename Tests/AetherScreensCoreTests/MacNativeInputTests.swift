#if canImport(AppKit)
import AppKit
import XCTest
@testable import AetherScreensCore

final class MacNativeInputTests: XCTestCase {
    @MainActor
    func testScaledPointerCoordinatesAndEdges() {
        let view = MacNativeInputView(frame: CGRect(x: 0, y: 0, width: 800, height: 450))
        view.remoteSize = CGSize(width: 3840, height: 2160)
        let center = view.translatePoint(NSPoint(x: 400, y: 225))
        XCTAssertEqual(center.0, 1920)
        XCTAssertEqual(center.1, 1080)
        let bottomRight = view.translatePoint(NSPoint(x: 900, y: -10))
        XCTAssertEqual(bottomRight.0, 3839)
        XCTAssertEqual(bottomRight.1, 2159)
        let topLeft = view.translatePoint(NSPoint(x: -10, y: 500))
        XCTAssertEqual(topLeft.0, 0)
        XCTAssertEqual(topLeft.1, 0)
    }

    @MainActor
    func testInputCompositionCommitsCompleteUnicodeKeyPairs() {
        let view = MacNativeInputView(frame: .zero)
        var events: [(Bool, UInt32)] = []
        view.onKeyEvent = { events.append(($0, $1)) }
        view.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(view.hasMarkedText())
        XCTAssertTrue(events.isEmpty)
        view.insertText("中a", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertFalse(view.hasMarkedText())
        XCTAssertEqual(events.map { $0.0 }, [true, false, true, false])
        XCTAssertEqual(events.map { $0.1 }, [0x01004E2D, 0x01004E2D, 0x61, 0x61])
    }

    @MainActor
    func testBackspaceAndKeyReleaseAfterModifiersChange() throws {
        let view = MacNativeInputView(frame: .zero)
        var events: [(Bool, UInt32)] = []
        view.onKeyEvent = { events.append(($0, $1)) }
        func event(_ type: NSEvent.EventType, code: UInt16, chars: String, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil, characters: chars,
                charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code))
        }
        view.keyDown(with: try event(.keyDown, code: 51, chars: "\u{7f}"))
        view.keyUp(with: try event(.keyUp, code: 51, chars: "\u{7f}"))
        XCTAssertEqual(events.map { $0.1 }, [MacKeyMap.backspace, MacKeyMap.backspace])
        events.removeAll()
        view.keyDown(with: try event(.keyDown, code: 0, chars: "a", flags: .command))
        view.keyUp(with: try event(.keyUp, code: 0, chars: "a"))
        XCTAssertEqual(events.map { $0.0 }, [true, false])
        XCTAssertEqual(events.map { $0.1 }, [0x61, 0x61])
    }

    func testPreciseWheelAccumulatesAndPreservesDirection() {
        var scroll = NativeScrollAccumulator()
        for _ in 0..<9 { XCTAssertTrue(scroll.consume(dx: 0, dy: -1, precise: true).isEmpty) }
        XCTAssertEqual(scroll.consume(dx: 0, dy: -1, precise: true), [.scrollDown])
        XCTAssertEqual(scroll.consume(dx: 20, dy: 30, precise: true), [.scrollUp, .scrollUp, .scrollUp, .scrollLeft, .scrollLeft])
        XCTAssertTrue(scroll.consume(dx: 0, dy: 0, precise: false).isEmpty)
        XCTAssertEqual(scroll.consume(dx: -2, dy: 0, precise: false), [.scrollRight, .scrollRight])
    }
}
#endif
