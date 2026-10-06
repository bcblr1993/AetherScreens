import Foundation
import CoreGraphics

#if canImport(AppKit)
import AppKit

/// macOS Native Input View capturing mouse tracking, hover, scroll wheel with momentum, and keyboard events.
public final class MacNativeInputView: NSView, NSTextInputClient {
    public var onPointerEvent: ((RFBConstants.ButtonMask, UInt16, UInt16) -> Void)?
    public var onKeyEvent: ((Bool, UInt32) -> Void)?
    public var onTextEvent: ((String) -> Void)?
    public var onInputReset: (() -> Void)?
    public var isPanning = false {
        didSet {
            if isPanning && !oldValue { releaseHeldInput() }
        }
    }
    public var onPan: ((CGFloat, CGFloat) -> Void)?
    private var lastPanPosition: NSPoint?
    public var remoteSize: CGSize = CGSize(width: 1920, height: 1080)

    private var trackingArea: NSTrackingArea?
    private var scrollAccumulator = NativeScrollAccumulator()
    private var markedText = NSAttributedString(string: "")
    private var pressedKeySyms: [UInt16: UInt32] = [:]
    private var transientKeySyms: [UUID: UInt32] = [:]
    private var pressedMouseButtons: RFBConstants.ButtonMask = []
    private var lastPointerPosition: (UInt16, UInt16) = (0, 0)
    private var inputEnabled = true
    private var dismantled = false
    private var inputRevision: UInt64 = 0
    private var inputReleaseDepth = 0

    public override var acceptsFirstResponder: Bool { true }

    public override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { releaseHeldInput() }
        return resigned
    }

    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil || newWindow !== window {
            inputEnabled = false
            releaseHeldInput()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && !dismantled { inputEnabled = true }
    }

    /// Clear local ownership before callbacks can rebuild the native view.
    private func releaseHeldInput() {
        let keyRelease = onKeyEvent
        let pointerRelease = onPointerEvent
        let resetTransport = onInputReset
        let outermostRelease = inputReleaseDepth == 0
        inputReleaseDepth += 1
        defer {
            if outermostRelease { resetTransport?() }
            inputReleaseDepth -= 1
        }
        var keys = Set(pressedKeySyms.values).union(transientKeySyms.values)
        for (flag, key) in [(NSEvent.ModifierFlags.command, MacKeyMap.commandLeft),
                            (.option, MacKeyMap.optionLeft), (.control, MacKeyMap.controlLeft),
                            (.shift, MacKeyMap.shiftLeft)] where lastModifierFlags.contains(flag) {
            keys.insert(key)
        }
        let buttons = pressedMouseButtons
        let position = lastPointerPosition
        inputRevision &+= 1
        pressedKeySyms.removeAll()
        transientKeySyms.removeAll()
        lastModifierFlags = []
        pressedMouseButtons = []
        lastPanPosition = nil
        scrollAccumulator = NativeScrollAccumulator()
        markedText = NSAttributedString(string: "")
        for key in keys.sorted() { keyRelease?(false, key) }
        if !buttons.isEmpty { pointerRelease?([], position.0, position.1) }
    }

    func invalidateInput() {
        guard !dismantled else { return }
        dismantled = true
        inputEnabled = false
        releaseHeldInput()
        onKeyEvent = nil
        onPointerEvent = nil
        onTextEvent = nil
        onPan = nil
        onInputReset = nil
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .activeInKeyWindow,
            .inVisibleRect
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        self.trackingArea = area
    }

    func translatePoint(_ viewPoint: NSPoint) -> (UInt16, UInt16) {
        guard bounds.width > 0, bounds.height > 0 else { return (0, 0) }
        // macOS AppKit has origin at bottom-left, flip to top-left for RFB
        let flippedY = bounds.height - viewPoint.y
        let scaleX = remoteSize.width / bounds.width
        let scaleY = remoteSize.height / bounds.height

        let x = UInt16(min(max(0, viewPoint.x * scaleX), max(0, remoteSize.width - 1)))
        let y = UInt16(min(max(0, flippedY * scaleY), max(0, remoteSize.height - 1)))
        return (x, y)
    }

    // MARK: - Mouse Events

    public override func mouseMoved(with event: NSEvent) {
        guard inputEnabled, !isPanning else { return }
        let (x, y) = translatePoint(convert(event.locationInWindow, from: nil))
        lastPointerPosition = (x, y)
        onPointerEvent?(pressedMouseButtons, x, y)
    }

    public override func mouseDown(with event: NSEvent) {
        guard inputEnabled else { return }
        let revision = inputRevision
        window?.makeFirstResponder(self)
        guard inputEnabled, inputRevision == revision else { return }
        if isPanning {
            lastPanPosition = convert(event.locationInWindow, from: nil)
            return
        }
        pressMouseButton(.left, event: event)
    }

    public override func mouseUp(with event: NSEvent) {
        guard inputEnabled else { return }
        if isPanning { lastPanPosition = nil; return }
        releaseMouseButton(.left, event: event)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard inputEnabled else { return }
        if isPanning {
            let point = convert(event.locationInWindow, from: nil)
            let revision = inputRevision
            if let old = lastPanPosition { onPan?(point.x - old.x, old.y - point.y) }
            guard inputEnabled, isPanning, inputRevision == revision else { return }
            lastPanPosition = point
            return
        }
        pressMouseButton(.left, event: event)
    }

    public override func rightMouseDown(with event: NSEvent) {
        pressMouseButton(.right, event: event)
    }

    public override func rightMouseUp(with event: NSEvent) {
        releaseMouseButton(.right, event: event)
    }

    public override func otherMouseDown(with event: NSEvent) {
        pressMouseButton(.middle, event: event)
    }

    public override func otherMouseUp(with event: NSEvent) {
        releaseMouseButton(.middle, event: event)
    }

    private func pressMouseButton(_ button: RFBConstants.ButtonMask, event: NSEvent) {
        guard inputEnabled, !isPanning else { return }
        pressedMouseButtons.insert(button)
        let (x, y) = translatePoint(convert(event.locationInWindow, from: nil))
        lastPointerPosition = (x, y)
        onPointerEvent?(pressedMouseButtons, x, y)
    }

    private func releaseMouseButton(_ button: RFBConstants.ButtonMask, event: NSEvent) {
        guard inputEnabled, !isPanning, pressedMouseButtons.contains(button) else { return }
        pressedMouseButtons.remove(button)
        let (x, y) = translatePoint(convert(event.locationInWindow, from: nil))
        lastPointerPosition = (x, y)
        onPointerEvent?(pressedMouseButtons, x, y)
    }

    public override func scrollWheel(with event: NSEvent) {
        guard inputEnabled, !isPanning else { return }
        let (x, y) = translatePoint(convert(event.locationInWindow, from: nil))
        lastPointerPosition = (x, y)
        let revision = inputRevision
        for mask in scrollAccumulator.consume(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas) {
            guard inputEnabled, !isPanning, inputRevision == revision else { return }
            onPointerEvent?(pressedMouseButtons.union(mask), x, y)
            guard inputEnabled, !isPanning, inputRevision == revision else { return }
            onPointerEvent?(pressedMouseButtons, x, y)
        }
    }

    // MARK: - Modifier Flags Tracking (Command, Option, Control, Shift)

    private var lastModifierFlags: NSEvent.ModifierFlags = []

    public override func flagsChanged(with event: NSEvent) {
        guard inputEnabled else { return }
        let current = event.modifierFlags
        let revision = inputRevision
        for (flag, key) in [(NSEvent.ModifierFlags.command, MacKeyMap.commandLeft),
                            (.option, MacKeyMap.optionLeft), (.control, MacKeyMap.controlLeft),
                            (.shift, MacKeyMap.shiftLeft)] {
            guard inputEnabled, inputRevision == revision else { return }
            let down = current.contains(flag)
            guard down != lastModifierFlags.contains(flag) else { continue }
            // Own only the transition being sent. A callback can dismantle the
            // view synchronously and must be able to balance this down then.
            if down { lastModifierFlags.insert(flag) }
            else { lastModifierFlags.remove(flag) }
            onKeyEvent?(down, key)
        }
    }

    // MARK: - Keyboard Events

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard inputEnabled else { return false }
        guard window?.firstResponder === self, event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        let revision = inputRevision
        flagsChanged(with: event)
        guard inputEnabled, inputRevision == revision else { return true }
        if let key = mapMacKeyCode(event.keyCode, characters: event.charactersIgnoringModifiers) {
            sendKeyStroke(key)
        }
        return true
    }

    public override func keyDown(with event: NSEvent) {
        guard inputEnabled else { return }
        let printable = event.characters?.unicodeScalars.allSatisfy {
            $0.value >= 0x20 && $0.value != 0x7F && $0.value < 0xF700
        } ?? false
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           hasMarkedText() || printable {
            interpretKeyEvents([event])
        } else if let key = mapMacKeyCode(event.keyCode, characters: !event.modifierFlags.intersection([.command, .control, .option]).isEmpty ? event.charactersIgnoringModifiers : event.characters) {
            pressedKeySyms[event.keyCode] = key
            onKeyEvent?(true, key)
        }
    }

    public override func keyUp(with event: NSEvent) {
        guard inputEnabled else { return }
        if let key = pressedKeySyms.removeValue(forKey: event.keyCode) {
            onKeyEvent?(false, key)
        }
    }

    public func insertText(_ string: Any, replacementRange: NSRange) {
        guard inputEnabled else { return }
        let text = (string as? NSAttributedString)?.string ?? (string as? String ?? "")
        markedText = NSAttributedString(string: "")
        if text.unicodeScalars.contains(where: { $0.value > 127 }) {
            AppLogger.shared.debug("Native composed text committed", category: "Input")
        }
        if let onTextEvent = onTextEvent {
            onTextEvent(text)
            return
        }
        let revision = inputRevision
        for character in text {
            guard inputEnabled, inputRevision == revision else { return }
            if let key = MacKeyMap.keySym(for: character), !sendKeyStroke(key) { return }
        }
    }

    /// Own a temporary key before its callback so synchronous cleanup can
    /// balance the down, then stop this event if cleanup changed the view.
    @discardableResult
    private func sendKeyStroke(_ key: UInt32) -> Bool {
        guard inputEnabled, let callback = onKeyEvent else { return false }
        let revision = inputRevision
        let token = UUID()
        transientKeySyms[token] = key
        callback(true, key)
        guard inputEnabled, inputRevision == revision else { return false }
        transientKeySyms.removeValue(forKey: token)
        callback(false, key)
        return inputEnabled && inputRevision == revision
    }

    public func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard inputEnabled else { return }
        markedText = (string as? NSAttributedString) ?? NSAttributedString(string: string as? String ?? "")
    }
    public func unmarkText() { markedText = NSAttributedString(string: "") }
    public func hasMarkedText() -> Bool { markedText.length > 0 }
    public func markedRange() -> NSRange { hasMarkedText() ? NSRange(location: 0, length: markedText.length) : NSRange(location: NSNotFound, length: 0) }
    public func selectedRange() -> NSRange { NSRange(location: markedText.length, length: 0) }
    public func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    public func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard range.location != NSNotFound, NSMaxRange(range) <= markedText.length else { return nil }
        actualRange?.pointee = range
        return markedText.attributedSubstring(from: range)
    }
    public func characterIndex(for point: NSPoint) -> Int { 0 }
    public func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        actualRange?.pointee = range
        return window?.convertToScreen(convert(NSRect(x: bounds.midX, y: bounds.midY, width: 1, height: 20), to: nil)) ?? .zero
    }

    private func mapMacKeyCode(_ keyCode: UInt16, characters: String?) -> UInt32? {
        switch keyCode {
        case 53: return MacKeyMap.escape
        case 48: return MacKeyMap.tab
        case 36: return MacKeyMap.return
        case 49: return MacKeyMap.space
        case 51: return MacKeyMap.backspace
        case 117: return MacKeyMap.delete
        case 123: return MacKeyMap.arrowLeft
        case 124: return MacKeyMap.arrowRight
        case 125: return MacKeyMap.arrowDown
        case 126: return MacKeyMap.arrowUp
        case 55, 54: return MacKeyMap.commandLeft
        case 58, 61: return MacKeyMap.optionLeft
        case 59, 62: return MacKeyMap.controlLeft
        case 56, 60: return MacKeyMap.shiftLeft
        // Function keys
        case 122: return MacKeyMap.f1
        case 120: return MacKeyMap.f2
        case 99:  return MacKeyMap.f3
        case 118: return MacKeyMap.f4
        case 96:  return MacKeyMap.f5
        case 97:  return MacKeyMap.f6
        case 98:  return MacKeyMap.f7
        case 100: return MacKeyMap.f8
        case 101: return MacKeyMap.f9
        case 109: return MacKeyMap.f10
        case 103: return MacKeyMap.f11
        case 111: return MacKeyMap.f12
        default:
            if let char = characters?.first, let sym = MacKeyMap.keySym(for: char) {
                return sym
            }
            return nil
        }
    }
}

import SwiftUI

/// SwiftUI representable wrapper for native mouse and keyboard input on macOS
public struct MacNativeInputRepresentable: NSViewRepresentable {
    public let onPointerEvent: (RFBConstants.ButtonMask, UInt16, UInt16) -> Void
    public let onKeyEvent: (Bool, UInt32) -> Void
    public let remoteWidth: CGFloat
    public let remoteHeight: CGFloat
    public let isPanning: Bool
    public let onPan: (CGFloat, CGFloat) -> Void
    public let onTextEvent: ((String) -> Void)?
    public let onInputReset: () -> Void

    public init(
        remoteWidth: CGFloat,
        remoteHeight: CGFloat,
        isPanning: Bool = false,
        onPan: @escaping (CGFloat, CGFloat) -> Void = { _, _ in },
        onTextEvent: ((String) -> Void)? = nil,
        onInputReset: @escaping () -> Void = {},
        onPointerEvent: @escaping (RFBConstants.ButtonMask, UInt16, UInt16) -> Void,
        onKeyEvent: @escaping (Bool, UInt32) -> Void
    ) {
        self.remoteWidth = remoteWidth
        self.remoteHeight = remoteHeight
        self.isPanning = isPanning
        self.onPan = onPan
        self.onTextEvent = onTextEvent
        self.onInputReset = onInputReset
        self.onPointerEvent = onPointerEvent
        self.onKeyEvent = onKeyEvent
    }

    public func makeNSView(context: Context) -> MacNativeInputView {
        let view = MacNativeInputView()
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel("Remote desktop input")
        view.isPanning = isPanning
        view.onPan = onPan
        view.onTextEvent = onTextEvent
        view.onInputReset = onInputReset
        view.remoteSize = CGSize(width: remoteWidth, height: remoteHeight)
        view.onPointerEvent = onPointerEvent
        view.onKeyEvent = onKeyEvent

        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    public func updateNSView(_ nsView: MacNativeInputView, context: Context) {
        nsView.isPanning = isPanning
        nsView.onPan = onPan
        nsView.onTextEvent = onTextEvent
        nsView.onInputReset = onInputReset
        nsView.remoteSize = CGSize(width: remoteWidth, height: remoteHeight)
        nsView.onPointerEvent = onPointerEvent
        nsView.onKeyEvent = onKeyEvent
    }

    public static func dismantleNSView(_ nsView: MacNativeInputView, coordinator: ()) {
        nsView.invalidateInput()
    }
}
#endif
