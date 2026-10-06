#if canImport(AppKit)
import AppKit
import CoreGraphics
import SwiftUI
import XCTest
@testable import AetherScreensCore

@MainActor
final class MacNativeInputLifecycleTests: XCTestCase {
    func testDismantleReleasesHeldInputBeforeClearingCallbacksAndRejectsLateEvents() throws {
        let (view, input) = makeView()
        let position = try holdKeyModifiersAndMouse(in: view, recording: input)

        MacNativeInputRepresentable.dismantleNSView(view, coordinator: ())

        assertBalancedRelease(input, at: position)
        XCTAssertNil(view.onKeyEvent)
        XCTAssertNil(view.onPointerEvent)
        XCTAssertNil(view.onTextEvent)
        let releasedKeys = input.keys
        let releasedPointers = input.pointers
        try sendLateEvents(to: view)
        MacNativeInputRepresentable.dismantleNSView(view, coordinator: ())
        view.viewWillMove(toWindow: nil)
        _ = view.resignFirstResponder()
        XCTAssertEqual(input.keys, releasedKeys)
        XCTAssertEqual(input.pointers, releasedPointers)
    }

    func testResignFirstResponderReleasesOnceAndRemainsReusable() throws {
        let (view, input) = makeView()
        let position = try holdKeyModifiersAndMouse(in: view, recording: input)

        _ = view.resignFirstResponder()

        assertBalancedRelease(input, at: position)
        let releasedKeys = input.keys
        let releasedPointers = input.pointers
        view.keyUp(with: try keyEvent(.keyUp))
        view.flagsChanged(with: try keyEvent(.flagsChanged, code: 56, characters: ""))
        view.mouseUp(with: try mouseEvent(.leftMouseUp))
        _ = view.resignFirstResponder()
        XCTAssertEqual(input.keys, releasedKeys, "Late key-up and repeated resignation must not release twice")
        XCTAssertEqual(input.pointers, releasedPointers)

        view.keyDown(with: try keyEvent(.keyDown))
        view.keyUp(with: try keyEvent(.keyUp))
        view.flagsChanged(with: try keyEvent(.flagsChanged, code: 56, characters: "", flags: .shift))
        view.flagsChanged(with: try keyEvent(.flagsChanged, code: 56, characters: ""))
        XCTAssertEqual(Array(input.keys.suffix(4)), [
            Key(down: true, symbol: MacKeyMap.arrowLeft),
            Key(down: false, symbol: MacKeyMap.arrowLeft),
            Key(down: true, symbol: MacKeyMap.shiftLeft),
            Key(down: false, symbol: MacKeyMap.shiftLeft)
        ], "Resignation must reset native ownership without permanently disabling input")
        view.mouseDown(with: try mouseEvent(.leftMouseDown))
        view.mouseUp(with: try mouseEvent(.leftMouseUp))
        XCTAssertEqual(input.pointers.suffix(2).map(\.mask), [1, 0])
    }

    func testRemovalFromWindowReleasesHeldInputAndSuppressesDetachedEvents() throws {
        let (view, input) = makeView()
        let position = try holdKeyModifiersAndMouse(in: view, recording: input)

        view.viewWillMove(toWindow: nil)

        assertBalancedRelease(input, at: position)
        let releasedKeys = input.keys
        let releasedPointers = input.pointers
        try sendLateEvents(to: view)
        view.viewWillMove(toWindow: nil)
        XCTAssertEqual(input.keys, releasedKeys)
        XCTAssertEqual(input.pointers, releasedPointers)
    }

    func testMouseButtonsRemainCombinedUntilEachButtonIsReleased() throws {
        let (view, input) = makeView()
        view.mouseDown(with: try mouseEvent(.leftMouseDown))
        view.rightMouseDown(with: try mouseEvent(.rightMouseDown))
        view.otherMouseDown(with: try mouseEvent(.otherMouseDown))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged))
        view.mouseUp(with: try mouseEvent(.leftMouseUp))
        view.rightMouseUp(with: try mouseEvent(.rightMouseUp))
        view.otherMouseUp(with: try mouseEvent(.otherMouseUp))

        XCTAssertEqual(input.pointers.map(\.mask), [1, 5, 7, 7, 6, 2, 0],
                       "An event for one physical button must preserve other held buttons")
        XCTAssertTrue(input.keys.isEmpty)
        let releasedPointers = input.pointers
        view.mouseUp(with: try mouseEvent(.leftMouseUp))
        view.rightMouseUp(with: try mouseEvent(.rightMouseUp))
        view.otherMouseUp(with: try mouseEvent(.otherMouseUp))
        XCTAssertEqual(input.pointers, releasedPointers, "Late button-up must not create a second release")
    }

    func testEnteringPanningReleasesHeldInputAndSuppressesPointerWhileKeepingKeyboardUsable() throws {
        let (view, input) = makeView()
        let position = try holdKeyModifiersAndMouse(in: view, recording: input)
        var panCount = 0
        view.onPan = { _, _ in panCount += 1 }

        view.isPanning = true

        assertBalancedRelease(input, at: position)
        let releasedPointers = input.pointers
        view.mouseMoved(with: try mouseEvent(.mouseMoved))
        view.mouseDown(with: try mouseEvent(.leftMouseDown))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, location: NSPoint(x: 60, y: 50)))
        view.rightMouseDown(with: try mouseEvent(.rightMouseDown))
        view.otherMouseDown(with: try mouseEvent(.otherMouseDown))
        view.mouseUp(with: try mouseEvent(.leftMouseUp))
        view.rightMouseUp(with: try mouseEvent(.rightMouseUp))
        view.otherMouseUp(with: try mouseEvent(.otherMouseUp))
        let wheel = try scrollEvent()
        XCTAssertNotEqual(wheel.scrollingDeltaY, 0, "The synthetic wheel must exercise nonzero input")
        view.scrollWheel(with: wheel)
        XCTAssertEqual(input.pointers, releasedPointers, "Pan mode must not send pointer or wheel input")
        XCTAssertEqual(panCount, 1, "Local viewport movement must still work")

        view.keyDown(with: try keyEvent(.keyDown))
        let heldKeys = input.keys
        view.isPanning = true
        XCTAssertEqual(input.keys, heldKeys, "An unchanged Pan value must not release a newly held keyboard key")
        view.keyUp(with: try keyEvent(.keyUp))
        XCTAssertEqual(Array(input.keys.suffix(2)), [
            Key(down: true, symbol: MacKeyMap.arrowLeft),
            Key(down: false, symbol: MacKeyMap.arrowLeft)
        ])
    }

    func testNativeLifecycleClearsMarkedTextWithoutCommittingIt() {
        for lifecycle in Lifecycle.allCases {
            let (view, input) = makeView()
            var committedText: [String] = []
            view.onTextEvent = { committedText.append($0) }
            // Set composition directly; no keyDown or interpretKeyEvents runs
            // while marked text exists, so this test never opens the system IME.
            view.setMarkedText("synthetic-marked", selectedRange: NSRange(location: 16, length: 0),
                               replacementRange: NSRange(location: NSNotFound, length: 0))
            XCTAssertTrue(view.hasMarkedText())

            switch lifecycle {
            case .dismantle: MacNativeInputRepresentable.dismantleNSView(view, coordinator: ())
            case .resign: _ = view.resignFirstResponder()
            case .detach: view.viewWillMove(toWindow: nil)
            case .panning: view.isPanning = true
            }

            XCTAssertFalse(view.hasMarkedText(), "Composition must be cleared on \(lifecycle)")
            XCTAssertEqual(view.markedRange().location, NSNotFound)
            XCTAssertTrue(committedText.isEmpty)
            XCTAssertTrue(input.keys.isEmpty)
            XCTAssertTrue(input.pointers.isEmpty, "An empty ownership state needs no synthetic pointer release")
        }
    }

    func testReleaseCallbackReentrantDismantleStillBalancesAllHeldInput() throws {
        let (view, input) = makeView()
        let position = try holdKeyModifiersAndMouse(in: view, recording: input)
        var reentered = false
        view.onKeyEvent = { [weak view] down, symbol in
            input.keys.append(Key(down: down, symbol: symbol))
            if !down && !reentered, let view {
                reentered = true
                MacNativeInputRepresentable.dismantleNSView(view, coordinator: ())
            }
        }

        _ = view.resignFirstResponder()

        XCTAssertTrue(reentered, "The first release callback must synchronously dismantle the view")
        assertBalancedRelease(input, at: position)
        XCTAssertNil(view.onKeyEvent)
        XCTAssertNil(view.onPointerEvent)
        let releasedKeys = input.keys
        let releasedPointers = input.pointers
        try sendLateEvents(to: view)
        MacNativeInputRepresentable.dismantleNSView(view, coordinator: ())
        XCTAssertEqual(input.keys, releasedKeys)
        XCTAssertEqual(input.pointers, releasedPointers)
    }

    func testModifierDownCallbackReentrantDismantleStopsUnreportedModifiersAndClearsOwnership() throws {
        let (view, input) = makeView()
        var reentered = false
        view.onKeyEvent = { [weak view] down, symbol in
            input.keys.append(Key(down: down, symbol: symbol))
            if down && !reentered, let view {
                reentered = true
                MacNativeInputRepresentable.dismantleNSView(view, coordinator: ())
            }
        }

        view.flagsChanged(with: try keyEvent(.flagsChanged, code: 56, characters: "",
                                            flags: [.command, .shift]))

        XCTAssertTrue(reentered)
        let expected = [Key(down: true, symbol: MacKeyMap.commandLeft),
                        Key(down: false, symbol: MacKeyMap.commandLeft)]
        XCTAssertEqual(input.keys, expected,
                       "Only the reported Command down may be released; the remaining Shift must never be sent")
        XCTAssertTrue(input.pointers.isEmpty)
        XCTAssertNil(view.onKeyEvent)
        XCTAssertNil(view.onPointerEvent)
        // Rebind only an observation sink before repeated cleanup, without
        // re-enabling the dismantled view, to detect revived modifier ownership.
        view.onKeyEvent = { input.keys.append(Key(down: $0, symbol: $1)) }
        MacNativeInputRepresentable.dismantleNSView(view, coordinator: ())
        XCTAssertEqual(input.keys, expected, "No modifier ownership may be restored after the callback returns")
        try sendLateEvents(to: view)
        XCTAssertEqual(input.keys, expected)
    }

    func testWheelCallbackReentrantLifecycleStopsRemainingOldWheelTicks() throws {
        for lifecycle in [Lifecycle.resign, .panning, .dismantle] {
            let (view, input) = makeView()
            var reentered = false
            view.onPointerEvent = { [weak view] mask, x, y in
                input.pointers.append(Pointer(mask: mask.rawValue, x: x, y: y))
                if mask.rawValue & 0x78 != 0 && !reentered, let view {
                    reentered = true
                    switch lifecycle {
                    case .resign: _ = view.resignFirstResponder()
                    case .panning: view.isPanning = true
                    case .dismantle: MacNativeInputRepresentable.dismantleNSView(view, coordinator: ())
                    case .detach: XCTFail("This case does not exercise detachment")
                    }
                }
            }
            let wheel = try scrollEvent()
            XCTAssertNotEqual(wheel.scrollingDeltaY, 0)

            view.scrollWheel(with: wheel)

            XCTAssertTrue(reentered, "The first wheel callback must synchronously enter \(lifecycle)")
            XCTAssertEqual(input.pointers.filter { $0.mask & 0x78 != 0 }.count, 1,
                           "The interrupted wheel event must stop its remaining ticks after \(lifecycle)")
            XCTAssertTrue(input.keys.isEmpty)
        }
    }

    func testFallbackTextDownCallbackReentrantDismantleBalancesOnlyReportedKey() {
        let (view, input) = makeView()
        view.onTextEvent = nil
        var reentered = false
        view.onKeyEvent = { [weak view] down, symbol in
            input.keys.append(Key(down: down, symbol: symbol))
            if down && !reentered, let view {
                reentered = true
                MacNativeInputRepresentable.dismantleNSView(view, coordinator: ())
            }
        }

        view.insertText("ab", replacementRange: NSRange(location: NSNotFound, length: 0))

        XCTAssertTrue(reentered)
        let expected = [Key(down: true, symbol: 0x61), Key(down: false, symbol: 0x61)]
        XCTAssertEqual(input.keys, expected,
                       "Cleanup must balance the reported a-down and suppress the remaining b transaction")
        XCTAssertTrue(input.pointers.isEmpty)
        XCTAssertNil(view.onKeyEvent)
        XCTAssertNil(view.onTextEvent)
        view.insertText("c", replacementRange: NSRange(location: NSNotFound, length: 0))
        MacNativeInputRepresentable.dismantleNSView(view, coordinator: ())
        XCTAssertEqual(input.keys, expected)
    }

    func testInputResetCallbackReentrantResignationDoesNotResetRecursively() throws {
        let (view, input) = makeView()
        let position = try holdKeyModifiersAndMouse(in: view, recording: input)
        var resetCalls = 0
        view.onInputReset = { [weak view] in
            resetCalls += 1
            guard resetCalls <= 2 else {
                XCTFail("Reentrant reset callbacks must remain bounded")
                return
            }
            if resetCalls == 1, let view {
                _ = view.resignFirstResponder()
            }
        }

        XCTAssertTrue(view.resignFirstResponder())

        assertBalancedRelease(input, at: position)
        XCTAssertEqual(resetCalls, 1, "The outer reset must remain active throughout its callback")
    }

    private enum Lifecycle: CaseIterable { case dismantle, resign, detach, panning }
    private struct Key: Equatable { let down: Bool; let symbol: UInt32 }
    private struct Pointer: Equatable { let mask: UInt8; let x: UInt16; let y: UInt16 }
    private final class Recording {
        var keys: [Key] = []
        var pointers: [Pointer] = []
    }

    private func makeView() -> (MacNativeInputView, Recording) {
        let view = MacNativeInputView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        view.remoteSize = CGSize(width: 400, height: 200)
        let input = Recording()
        view.onKeyEvent = { input.keys.append(Key(down: $0, symbol: $1)) }
        view.onPointerEvent = { input.pointers.append(Pointer(mask: $0.rawValue, x: $1, y: $2)) }
        view.onTextEvent = { _ in XCTFail("Nonprintable synthetic events must not commit text") }
        return (view, input)
    }

    private func holdKeyModifiersAndMouse(in view: MacNativeInputView, recording input: Recording,
                                         file: StaticString = #filePath, line: UInt = #line) throws -> Pointer {
        view.keyDown(with: try keyEvent(.keyDown))
        view.flagsChanged(with: try keyEvent(.flagsChanged, code: 56, characters: "", flags: [.command, .shift]))
        view.mouseDown(with: try mouseEvent(.leftMouseDown))
        XCTAssertEqual(input.keys, [Key(down: true, symbol: MacKeyMap.arrowLeft),
                                   Key(down: true, symbol: MacKeyMap.commandLeft),
                                   Key(down: true, symbol: MacKeyMap.shiftLeft)], file: file, line: line)
        XCTAssertEqual(input.pointers.count, 1, file: file, line: line)
        XCTAssertEqual(input.pointers.first?.mask, 1, file: file, line: line)
        return try XCTUnwrap(input.pointers.last, file: file, line: line)
    }

    private func assertBalancedRelease(_ input: Recording, at position: Pointer,
                                       file: StaticString = #filePath, line: UInt = #line) {
        let released = input.keys.filter { !$0.down }
        XCTAssertEqual(input.keys.count, 6, file: file, line: line)
        XCTAssertEqual(released.count, 3, file: file, line: line)
        XCTAssertEqual(Set(released.map(\.symbol)),
                       Set([MacKeyMap.arrowLeft, MacKeyMap.commandLeft, MacKeyMap.shiftLeft]), file: file, line: line)
        XCTAssertEqual(input.pointers, [position, Pointer(mask: 0, x: position.x, y: position.y)], file: file, line: line)
    }

    private func sendLateEvents(to view: MacNativeInputView) throws {
        view.keyUp(with: try keyEvent(.keyUp))
        view.flagsChanged(with: try keyEvent(.flagsChanged, code: 56, characters: ""))
        view.mouseUp(with: try mouseEvent(.leftMouseUp))
        view.keyDown(with: try keyEvent(.keyDown))
        view.flagsChanged(with: try keyEvent(.flagsChanged, code: 58, characters: "", flags: .option))
        view.mouseDown(with: try mouseEvent(.leftMouseDown))
    }

    private func keyEvent(_ type: NSEvent.EventType, code: UInt16 = 123,
                          characters: String = "\u{F702}", flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
            timestamp: 0, windowNumber: 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
    }

    private func mouseEvent(_ type: NSEvent.EventType, location: NSPoint = NSPoint(x: 40, y: 60)) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }

    private func scrollEvent() throws -> NSEvent {
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                                        wheel1: 4, wheel2: 0, wheel3: 0))
        return try XCTUnwrap(NSEvent(cgEvent: event))
    }
}
#endif
