#if canImport(AppKit)
import AppKit
import XCTest
@testable import AetherScreensCore

final class MacNativeInputTests: XCTestCase {
    @MainActor
    func testHeldRemoteDragTakesPriorityOverLocalMagnification() throws {
        let view = MacNativeInputView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        var zooms = 0
        view.onMagnification = { _, _ in zooms += 1 }
        func event(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: 200, y: 150),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1))
        }
        view.mouseDown(with: try event(.leftMouseDown))
        view.magnify(delta: 0.2, at: NSPoint(x: 200, y: 150))
        XCTAssertEqual(zooms, 0)
        view.mouseUp(with: try event(.leftMouseUp))
        view.magnify(delta: 0.2, at: NSPoint(x: 200, y: 150))
        XCTAssertEqual(zooms, 1)
    }

    @MainActor
    func testMagnificationUsesVisibleViewportAnchorWithoutRemotePointerEvents() {
        let view = MacNativeInputView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.viewport = CGRect(x: 395, y: 0, width: 400, height: 300)
        var samples: [(CGFloat, CGPoint)] = []
        view.onMagnification = { samples.append(($0, $1)) }
        view.onPointerEvent = { _, _, _ in XCTFail("Local zoom must not move remote pointer") }
        view.magnify(delta: 0.2, at: NSPoint(x: 595, y: 450))
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].0, 1.2, accuracy: 0.001)
        XCTAssertEqual(samples[0].1, CGPoint(x: 200, y: 150))
        for delta: CGFloat in [0, -1, -.infinity, .nan] {
            view.magnify(delta: delta, at: .zero)
        }
        XCTAssertEqual(samples.count, 1)
    }

    @MainActor
    func testScrollPhasesResetGestureAndPreserveMomentumHandoff() throws {
        let view = MacNativeInputView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        view.remoteSize = CGSize(width: 400, height: 300)
        var masks: [RFBConstants.ButtonMask] = []
        view.onPointerEvent = { mask, _, _ in masks.append(mask) }
        func scroll(_ delta: Int32, phase: Int64, momentum: Int64 = 0) throws {
            let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0))
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
            let native = try XCTUnwrap(NSEvent(cgEvent: event))
            XCTAssertTrue(native.hasPreciseScrollingDeltas)
            let expected: NSEvent.Phase
            switch phase {
            case 1: expected = .began
            case 2: expected = .changed
            case 4: expected = .ended
            case 8: expected = .cancelled
            default: expected = []
            }
            XCTAssertEqual(native.phase, expected)
            view.scrollWheel(with: native)
        }
        try scroll(9, phase: 1)
        try scroll(9, phase: 1) // New gesture discards the previous nine points.
        XCTAssertTrue(masks.isEmpty)
        try scroll(1, phase: 8) // Cancellation neither scrolls nor retains remainder.
        try scroll(1, phase: 2)
        XCTAssertTrue(masks.isEmpty)
        try scroll(9, phase: 2)
        XCTAssertEqual(masks, [.scrollUp, []])
        masks.removeAll()
        try scroll(9, phase: 1)
        try scroll(0, phase: 4)
        try scroll(1, phase: 0, momentum: 1)
        XCTAssertEqual(masks, [.scrollUp, []])
    }

    func testSwitchingScrollDeviceDoesNotCarryFractionalTicks() {
        var scroll = ScrollWheelAccumulator()
        XCTAssertTrue(scroll.consume(dx: 9, dy: 9, precise: true).isEmpty)
        XCTAssertEqual(scroll.consume(dx: -1, dy: -1, precise: false), [.scrollDown, .scrollRight])
        XCTAssertTrue(scroll.consume(dx: 0.9, dy: 0.9, precise: false).isEmpty)
        XCTAssertTrue(scroll.consume(dx: 1, dy: 1, precise: true).isEmpty)
        XCTAssertEqual(scroll.consume(dx: 9, dy: 9, precise: true), [.scrollUp, .scrollLeft])
    }

    @MainActor
    func testConsecutiveEdgeSamplesClampBeforeLayoutCatchesUp() {
        let view = MacNativeInputView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.viewport = CGRect(x: 395, y: 0, width: 400, height: 300)
        var pans: [CGSize] = []
        view.onPan = { pans.append(CGSize(width: $0, height: $1)) }
        XCTAssertEqual(view.followPointer(NSPoint(x: 795, y: 450),
            movement: CGSize(width: 10, height: 0)), NSPoint(x: 800, y: 450))
        // A frame/toolbar update may resend unchanged layout before the pan.
        view.viewport = CGRect(x: 395, y: 0, width: 400, height: 300)
        XCTAssertEqual(view.followPointer(NSPoint(x: 796, y: 450),
            movement: CGSize(width: 1, height: 0)), NSPoint(x: 801, y: 450))
        XCTAssertEqual(pans, [CGSize(width: -5, height: 0)])
        XCTAssertEqual(view.followPointer(NSPoint(x: 796, y: 450), movement: .zero),
            NSPoint(x: 801, y: 450))
        // Once layout applies the pan, incoming coordinates already include it.
        view.viewport = CGRect(x: 400, y: 0, width: 400, height: 300)
        XCTAssertEqual(view.followPointer(NSPoint(x: 801, y: 450), movement: .zero),
            NSPoint(x: 801, y: 450))
        XCTAssertEqual(pans.count, 1)
    }

    @MainActor
    func testZoomedViewportFollowsEdgesAndMapsPointerAfterPan() {
        let view = MacNativeInputView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.remoteSize = CGSize(width: 1920, height: 1080)
        view.viewport = CGRect(x: 200, y: 150, width: 400, height: 300)
        var pans: [CGSize] = []
        view.onPan = { pans.append(CGSize(width: $0, height: $1)) }
        let mapped = view.followPointer(NSPoint(x: 590, y: 160),
            movement: CGSize(width: 10, height: 10))
        XCTAssertEqual(pans, [CGSize(width: -22, height: -22)])
        XCTAssertEqual(mapped, NSPoint(x: 612, y: 138))
        let remote = view.translatePoint(mapped)
        XCTAssertEqual(remote.0, 1468)
        XCTAssertEqual(remote.1, 831)
        _ = view.followPointer(NSPoint(x: 590, y: 160), movement: .zero)
        XCTAssertEqual(pans.count, 1)
        view.isPanning = true
        _ = view.followPointer(NSPoint(x: 590, y: 160), movement: CGSize(width: 10, height: 10))
        XCTAssertEqual(pans.count, 1)
    }

    @MainActor
    func testMouseChordAndFocusCleanupPreserveOtherButtons() throws {
        let view = MacNativeInputView(frame: CGRect(x: 0, y: 0, width: 800, height: 450))
        view.remoteSize = CGSize(width: 800, height: 450)
        var masks: [RFBConstants.ButtonMask] = []
        view.onPointerEvent = { mask, _, _ in masks.append(mask) }
        func event(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: 100, y: 200),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1))
        }
        view.mouseDown(with: try event(.leftMouseDown))
        view.rightMouseDown(with: try event(.rightMouseDown))
        view.mouseUp(with: try event(.leftMouseUp))
        view.rightMouseDragged(with: try event(.rightMouseDragged))
        view.releaseRemoteInput()
        view.releaseRemoteInput()
        XCTAssertEqual(masks, [.left, [.left, .right], .right, .right, []])
        masks.removeAll()
        let middle = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown,
            mouseCursorPosition: CGPoint(x: 100, y: 200), mouseButton: .center))
        view.otherMouseDown(with: try XCTUnwrap(NSEvent(cgEvent: middle)))
        view.isPanning = true
        view.rightMouseDown(with: try event(.rightMouseDown))
        view.otherMouseDragged(with: try event(.otherMouseDragged))
        XCTAssertEqual(masks, [.middle, []])
    }

    @MainActor
    func testEnteringPanReleasesRemoteLeftDragAtLastPosition() throws {
        let view = MacNativeInputView(frame: CGRect(x: 0, y: 0, width: 800, height: 450))
        view.remoteSize = CGSize(width: 800, height: 450)
        var events: [(RFBConstants.ButtonMask, UInt16, UInt16)] = []
        view.onPointerEvent = { events.append(($0, $1, $2)) }
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
            location: NSPoint(x: 100, y: 200), modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        view.mouseDown(with: down)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].0, .left)
        view.isPanning = true
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[1].0, [])
        XCTAssertEqual(events[1].1, events[0].1)
        XCTAssertEqual(events[1].2, events[0].2)
        view.isPanning = true
        view.releaseRemoteInput()
        XCTAssertEqual(events.count, 2)
    }

    @MainActor
    func testFocusCleanupReleasesKeysOnceAndClearsComposition() throws {
        let view = MacNativeInputView(frame: .zero)
        var events: [(Bool, UInt32)] = []
        view.onKeyEvent = { events.append(($0, $1)) }
        let key = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command, .shift], timestamp: 0, windowNumber: 0,
            context: nil, characters: "a", charactersIgnoringModifiers: "a",
            isARepeat: false, keyCode: 0))
        view.flagsChanged(with: key)
        view.keyDown(with: key)
        view.setMarkedText("pending", selectedRange: NSRange(location: 7, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        events.removeAll()
        view.releaseRemoteInput()
        XCTAssertFalse(view.hasMarkedText())
        XCTAssertEqual(Set(events.map { $0.1 }), [MacKeyMap.commandLeft, MacKeyMap.shiftLeft, 0x61])
        XCTAssertTrue(events.allSatisfy { !$0.0 })
        XCTAssertEqual(events.count, 3)
        view.releaseRemoteInput()
        view.keyUp(with: key)
        XCTAssertEqual(events.count, 3)
    }

    @MainActor
    func testWindowResignNotificationAndDetachmentReleaseRecordedKey() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = MacNativeInputView(frame: window.contentView!.bounds)
        window.contentView = view
        defer { window.contentView = NSView(); window.close() }
        let released = expectation(description: "Window notification releases recorded key")
        var releaseCount = 0
        view.onKeyEvent = { down, key in
            if !down, key == MacKeyMap.escape {
                releaseCount += 1
                if releaseCount == 1 { released.fulfill() }
            }
        }
        let key = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53))
        view.keyDown(with: key)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        wait(for: [released], timeout: 3)
        XCTAssertEqual(releaseCount, 1)
        view.keyDown(with: key)
        window.contentView = NSView()
        XCTAssertEqual(releaseCount, 2)
        view.releaseRemoteInput()
        XCTAssertEqual(releaseCount, 2)
    }

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

    func testCappedScrollDoesNotReplayOverflowOrDelayDirectionChange() {
        var scroll = ScrollWheelAccumulator()
        XCTAssertEqual(scroll.consume(dx: 0, dy: 1000.25, precise: false),
                       Array(repeating: .scrollUp, count: 64))
        XCTAssertTrue(scroll.consume(dx: 0, dy: 0, precise: false).isEmpty)
        XCTAssertEqual(scroll.consume(dx: 0, dy: -1.25, precise: false), [.scrollDown])
        XCTAssertEqual(scroll.consume(dx: .greatestFiniteMagnitude, dy: 0, precise: false),
                       Array(repeating: .scrollLeft, count: 64))
        XCTAssertTrue(scroll.consume(dx: 0, dy: 0, precise: false).isEmpty)
        XCTAssertTrue(scroll.consume(dx: .nan, dy: .infinity, precise: true).isEmpty)
        XCTAssertEqual(scroll.consume(dx: 0, dy: -10, precise: true), [.scrollDown])
    }

    func testTouchScrollKeepsEightPointStepsAndBoundsBurst() {
        var scroll = ScrollWheelAccumulator()
        XCTAssertTrue(scroll.consume(dx: 0, dy: 7, precise: true, preciseDivisor: 8).isEmpty)
        XCTAssertEqual(scroll.consume(dx: 0, dy: 1, precise: true, preciseDivisor: 8), [.scrollUp])
        XCTAssertEqual(scroll.consume(dx: -16, dy: 24, precise: true, preciseDivisor: 8),
                       [.scrollUp, .scrollUp, .scrollUp, .scrollRight, .scrollRight])
        XCTAssertEqual(scroll.consume(dx: 0, dy: 8000, precise: true, preciseDivisor: 8).count, 64)
        XCTAssertTrue(scroll.consume(dx: 0, dy: 0, precise: true, preciseDivisor: 8).isEmpty)
        XCTAssertTrue(scroll.consume(dx: 1, dy: 1, precise: true, preciseDivisor: 0).isEmpty)
    }

    func testPreciseWheelAccumulatesAndPreservesDirection() {
        var scroll = ScrollWheelAccumulator()
        for _ in 0..<9 { XCTAssertTrue(scroll.consume(dx: 0, dy: -1, precise: true).isEmpty) }
        XCTAssertEqual(scroll.consume(dx: 0, dy: -1, precise: true), [.scrollDown])
        XCTAssertEqual(scroll.consume(dx: 20, dy: 30, precise: true), [.scrollUp, .scrollUp, .scrollUp, .scrollLeft, .scrollLeft])
        XCTAssertTrue(scroll.consume(dx: 0, dy: 0, precise: false).isEmpty)
        XCTAssertEqual(scroll.consume(dx: -2, dy: 0, precise: false), [.scrollRight, .scrollRight])
    }
}
#endif
