import Foundation
import CoreGraphics

#if canImport(AppKit)
import AppKit
import Combine

/// macOS Native Input View capturing mouse tracking, hover, scroll wheel with momentum, and keyboard events.
public final class MacNativeInputView: NSView, NSTextInputClient {
    public var onPointerEvent: ((RFBConstants.ButtonMask, UInt16, UInt16) -> Void)?
    public var onKeyEvent: ((Bool, UInt32) -> Void)?
    public var onTextEvent: ((String) -> Void)?
    public var isPanning = false {
        didSet {
            guard oldValue != isPanning else { return }
            if isPanning, !remoteButtons.isEmpty, let position = remotePointerPosition {
                remotePointerPosition = nil
                remoteButtons = []
                onPointerEvent?([], position.x, position.y)
            }
            lastPanPosition = nil
            lastPointerWindowLocation = nil
            window?.invalidateCursorRects(for: self)
        }
    }
    var cursorSubscription: AnyCancellable?
    private var windowFocusSubscription: AnyCancellable?
    private(set) var remoteCursor: NSCursor = .arrow

    func setRemoteCursor(_ shape: RFBRemoteCursor?) {
        if let shape {
            if let image = shape.makeCGImage() {
                remoteCursor = NSCursor(image: NSImage(cgImage: image,
                    size: NSSize(width: shape.width, height: shape.height)),
                    hotSpot: NSPoint(x: shape.hotspotX, y: shape.hotspotY))
            } else if shape.isHidden {
                remoteCursor = NSCursor(image: NSImage(size: NSSize(width: 1, height: 1)), hotSpot: .zero)
            } else {
                remoteCursor = .arrow
            }
        } else { remoteCursor = .arrow }
        window?.invalidateCursorRects(for: self)
    }

    public override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(visibleRect, cursor: isPanning ? .openHand : remoteCursor)
    }
    public var onPan: ((CGFloat, CGFloat) -> Void)?
    public var onMagnification: ((CGFloat, CGPoint) -> Void)?
    private var lastPanPosition: NSPoint?
    private var lastPointerWindowLocation: NSPoint?
    var viewport: CGRect? {
        didSet {
            // An unrelated SwiftUI update can resend the old geometry before
            // the requested pan reaches layout. Keep its pointer correction.
            if viewport != oldValue { pendingViewportPan = .zero }
        }
    }
    private var pendingViewportPan: CGSize = .zero
    private var remotePointerPosition: (x: UInt16, y: UInt16)?
    private var remoteButtons: RFBConstants.ButtonMask = []
    public var remoteSize: CGSize = CGSize(width: 1920, height: 1080)

    private var trackingArea: NSTrackingArea?
    private var scrollAccumulator = ScrollWheelAccumulator()
    private var markedText = NSAttributedString(string: "")
    private var pressedKeySyms: [UInt16: UInt32] = [:]

    public override var acceptsFirstResponder: Bool { true }

    func releaseRemoteInput() {
        var keys = Set(pressedKeySyms.values)
        for (flag, key) in [(NSEvent.ModifierFlags.command, MacKeyMap.commandLeft),
                            (.option, MacKeyMap.optionLeft), (.control, MacKeyMap.controlLeft),
                            (.shift, MacKeyMap.shiftLeft)] where lastModifierFlags.contains(flag) {
            keys.insert(key)
        }
        let drag = remoteButtons.isEmpty ? nil : remotePointerPosition
        // Clear first: outgoing callbacks may synchronously change focus again.
        pressedKeySyms.removeAll()
        lastModifierFlags = []
        remotePointerPosition = nil
        remoteButtons = []
        lastPanPosition = nil
        lastPointerWindowLocation = nil
        scrollAccumulator = ScrollWheelAccumulator()
        markedText = NSAttributedString(string: "")
        for key in keys.sorted() { onKeyEvent?(false, key) }
        if let drag { onPointerEvent?([], drag.x, drag.y) }
    }

    public override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { releaseRemoteInput() }
        return resigned
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        releaseRemoteInput()
        windowFocusSubscription = nil
        if let window {
            windowFocusSubscription = NotificationCenter.default.publisher(
                for: NSWindow.didResignKeyNotification, object: window)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.releaseRemoteInput() }
        }
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

    public override func magnify(with event: NSEvent) {
        guard !event.phase.contains(.cancelled) else { return }
        magnify(delta: event.magnification, at: convert(event.locationInWindow, from: nil))
    }

    func magnify(delta: CGFloat, at point: NSPoint) {
        guard delta.isFinite, delta > -1, delta != 0, remoteButtons.isEmpty else { return }
        let visible = viewport ?? bounds
        let anchor = CGPoint(x: point.x - visible.minX,
                             y: bounds.height - point.y - visible.minY)
        onMagnification?(1 + delta, anchor)
    }

    func followPointer(_ point: NSPoint, movement: CGSize) -> NSPoint {
        guard let viewport, !isPanning else { return point }
        // Account for pan requests not yet reflected in the SwiftUI layout.
        let projectedPoint = NSPoint(x: point.x - pendingViewportPan.width,
                                     y: point.y + pendingViewportPan.height)
        let projectedViewport = viewport.offsetBy(dx: -pendingViewportPan.width,
                                                   dy: -pendingViewportPan.height)
        let delta = ViewportTracking.panDelta(canvas: bounds, viewport: projectedViewport,
            pointer: CGPoint(x: projectedPoint.x, y: bounds.height - projectedPoint.y), movement: movement)
        pendingViewportPan.width += delta.width
        pendingViewportPan.height += delta.height
        if delta != .zero { onPan?(delta.width, delta.height) }
        return NSPoint(x: projectedPoint.x - delta.width, y: projectedPoint.y + delta.height)
    }

    private func sendPointer(with event: NSEvent) {
        let windowPoint = event.locationInWindow
        let movement = lastPointerWindowLocation.map {
            CGSize(width: windowPoint.x - $0.x, height: $0.y - windowPoint.y)
        } ?? .zero
        lastPointerWindowLocation = windowPoint
        let follows = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged].contains(event.type)
        let point = convert(windowPoint, from: nil)
        let mapped = followPointer(point, movement: follows ? movement : .zero)
        let (x, y) = translatePoint(mapped)
        remotePointerPosition = (x, y)
        onPointerEvent?(remoteButtons, x, y)
    }

    public override func mouseMoved(with event: NSEvent) {
        guard !isPanning else { return }
        sendPointer(with: event)
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if isPanning {
            lastPanPosition = convert(event.locationInWindow, from: nil)
            return
        }
        remoteButtons.insert(.left)
        sendPointer(with: event)
    }

    public override func mouseUp(with event: NSEvent) {
        if isPanning { lastPanPosition = nil; return }
        remoteButtons.remove(.left)
        sendPointer(with: event)
    }

    public override func mouseDragged(with event: NSEvent) {
        if isPanning {
            let point = convert(event.locationInWindow, from: nil)
            if let old = lastPanPosition { onPan?(point.x - old.x, old.y - point.y) }
            lastPanPosition = point
            return
        }
        sendPointer(with: event)
    }

    public override func rightMouseDown(with event: NSEvent) {
        guard !isPanning else { return }
        window?.makeFirstResponder(self)
        remoteButtons.insert(.right)
        sendPointer(with: event)
    }

    public override func rightMouseUp(with event: NSEvent) {
        guard !isPanning else { return }
        remoteButtons.remove(.right)
        sendPointer(with: event)
    }

    public override func rightMouseDragged(with event: NSEvent) {
        guard !isPanning else { return }
        sendPointer(with: event)
    }

    public override func otherMouseDown(with event: NSEvent) {
        guard !isPanning, event.buttonNumber == 2 else { return }
        window?.makeFirstResponder(self)
        remoteButtons.insert(.middle)
        sendPointer(with: event)
    }

    public override func otherMouseUp(with event: NSEvent) {
        guard !isPanning, event.buttonNumber == 2 else { return }
        remoteButtons.remove(.middle)
        sendPointer(with: event)
    }

    public override func otherMouseDragged(with event: NSEvent) {
        guard !isPanning, event.buttonNumber == 2 else { return }
        sendPointer(with: event)
    }

    public override func scrollWheel(with event: NSEvent) {
        guard !isPanning else { return }
        if event.phase.contains(.began) || event.phase.contains(.cancelled) {
            scrollAccumulator = ScrollWheelAccumulator()
        }
        guard !event.phase.contains(.cancelled) else { return }
        let point = followPointer(convert(event.locationInWindow, from: nil), movement: .zero)
        let (x, y) = translatePoint(point)
        remotePointerPosition = (x, y)
        for mask in scrollAccumulator.consume(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas) {
            onPointerEvent?(remoteButtons.union(mask), x, y)
            onPointerEvent?(remoteButtons, x, y)
        }
    }

    // MARK: - Modifier Flags Tracking (Command, Option, Control, Shift)

    private var lastModifierFlags: NSEvent.ModifierFlags = []

    public override func flagsChanged(with event: NSEvent) {
        let current = event.modifierFlags
        // Command
        if current.contains(.command) != lastModifierFlags.contains(.command) {
            onKeyEvent?(current.contains(.command), MacKeyMap.commandLeft)
        }
        // Option
        if current.contains(.option) != lastModifierFlags.contains(.option) {
            onKeyEvent?(current.contains(.option), MacKeyMap.optionLeft)
        }
        // Control
        if current.contains(.control) != lastModifierFlags.contains(.control) {
            onKeyEvent?(current.contains(.control), MacKeyMap.controlLeft)
        }
        // Shift
        if current.contains(.shift) != lastModifierFlags.contains(.shift) {
            onKeyEvent?(current.contains(.shift), MacKeyMap.shiftLeft)
        }
        lastModifierFlags = current
    }

    // MARK: - Keyboard Events

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        flagsChanged(with: event)
        if let key = mapMacKeyCode(event.keyCode, characters: event.charactersIgnoringModifiers) {
            onKeyEvent?(true, key)
            onKeyEvent?(false, key)
        }
        return true
    }

    public override func keyDown(with event: NSEvent) {
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
        if let key = pressedKeySyms.removeValue(forKey: event.keyCode) {
            onKeyEvent?(false, key)
        }
    }

    public func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? (string as? String ?? "")
        markedText = NSAttributedString(string: "")
        if text.unicodeScalars.contains(where: { $0.value > 127 }) {
            AppLogger.shared.debug("Native composed text committed", category: "Input")
        }
        if let onTextEvent = onTextEvent {
            onTextEvent(text)
            return
        }
        for character in text {
            if let key = MacKeyMap.keySym(for: character) {
                onKeyEvent?(true, key)
                onKeyEvent?(false, key)
            }
        }
    }

    public func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
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
    public let cursorUpdates: CurrentValueSubject<RFBRemoteCursor?, Never>?
    public let onPointerEvent: (RFBConstants.ButtonMask, UInt16, UInt16) -> Void
    public let onKeyEvent: (Bool, UInt32) -> Void
    public let remoteWidth: CGFloat
    public let remoteHeight: CGFloat
    public let viewport: CGRect?
    public let isPanning: Bool
    public let onPan: (CGFloat, CGFloat) -> Void
    public let onMagnification: ((CGFloat, CGPoint) -> Void)?
    public let onTextEvent: ((String) -> Void)?

    public init(
        cursorUpdates: CurrentValueSubject<RFBRemoteCursor?, Never>? = nil,
        remoteWidth: CGFloat,
        remoteHeight: CGFloat,
        viewport: CGRect? = nil,
        isPanning: Bool = false,
        onPan: @escaping (CGFloat, CGFloat) -> Void = { _, _ in },
        onMagnification: ((CGFloat, CGPoint) -> Void)? = nil,
        onTextEvent: ((String) -> Void)? = nil,
        onPointerEvent: @escaping (RFBConstants.ButtonMask, UInt16, UInt16) -> Void,
        onKeyEvent: @escaping (Bool, UInt32) -> Void
    ) {
        self.cursorUpdates = cursorUpdates
        self.remoteWidth = remoteWidth
        self.remoteHeight = remoteHeight
        self.viewport = viewport
        self.isPanning = isPanning
        self.onPan = onPan
        self.onMagnification = onMagnification
        self.onTextEvent = onTextEvent
        self.onPointerEvent = onPointerEvent
        self.onKeyEvent = onKeyEvent
    }

    public func makeNSView(context: Context) -> MacNativeInputView {
        let view = MacNativeInputView()
        view.cursorSubscription = cursorUpdates?.sink { [weak view] shape in
            view?.setRemoteCursor(shape)
        }
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel("Remote desktop input")
        view.isPanning = isPanning
        view.viewport = viewport
        view.onPan = onPan
        view.onMagnification = onMagnification
        view.onTextEvent = onTextEvent
        view.remoteSize = CGSize(width: remoteWidth, height: remoteHeight)
        view.onPointerEvent = onPointerEvent
        view.onKeyEvent = onKeyEvent

        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    public static func dismantleNSView(_ nsView: MacNativeInputView, coordinator: ()) {
        nsView.releaseRemoteInput()
        nsView.cursorSubscription = nil
    }

    public func updateNSView(_ nsView: MacNativeInputView, context: Context) {
        nsView.isPanning = isPanning
        nsView.viewport = viewport
        nsView.onPan = onPan
        nsView.onMagnification = onMagnification
        nsView.onTextEvent = onTextEvent
        nsView.remoteSize = CGSize(width: remoteWidth, height: remoteHeight)
        nsView.onPointerEvent = onPointerEvent
        nsView.onKeyEvent = onKeyEvent
    }
}
#endif
