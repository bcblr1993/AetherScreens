import Foundation
import CoreGraphics

#if canImport(AppKit)
import AppKit

/// macOS Native Input View capturing mouse tracking, hover, scroll wheel with momentum, and keyboard events.
public final class MacNativeInputView: NSView {
    public var onPointerEvent: ((RFBConstants.ButtonMask, UInt16, UInt16) -> Void)?
    public var onKeyEvent: ((Bool, UInt32) -> Void)?
    public var remoteSize: CGSize = CGSize(width: 1920, height: 1080)

    private var trackingArea: NSTrackingArea?

    public override var acceptsFirstResponder: Bool { true }

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

    private func translatePoint(_ viewPoint: NSPoint) -> (UInt16, UInt16) {
        guard bounds.width > 0, bounds.height > 0 else { return (0, 0) }
        // macOS AppKit has origin at bottom-left, flip to top-left for RFB
        let flippedY = bounds.height - viewPoint.y
        let scaleX = remoteSize.width / bounds.width
        let scaleY = remoteSize.height / bounds.height

        let x = UInt16(min(max(0, viewPoint.x * scaleX), remoteSize.width))
        let y = UInt16(min(max(0, flippedY * scaleY), remoteSize.height))
        return (x, y)
    }

    // MARK: - Mouse Events

    public override func mouseMoved(with event: NSEvent) {
        let (x, y) = translatePoint(convert(event.locationInWindow, from: nil))
        onPointerEvent?([], x, y)
    }

    public override func mouseDown(with event: NSEvent) {
        let (x, y) = translatePoint(convert(event.locationInWindow, from: nil))
        onPointerEvent?([.left], x, y)
    }

    public override func mouseUp(with event: NSEvent) {
        let (x, y) = translatePoint(convert(event.locationInWindow, from: nil))
        onPointerEvent?([], x, y)
    }

    public override func mouseDragged(with event: NSEvent) {
        let (x, y) = translatePoint(convert(event.locationInWindow, from: nil))
        onPointerEvent?([.left], x, y)
    }

    public override func rightMouseDown(with event: NSEvent) {
        let (x, y) = translatePoint(convert(event.locationInWindow, from: nil))
        onPointerEvent?([.right], x, y)
    }

    public override func rightMouseUp(with event: NSEvent) {
        let (x, y) = translatePoint(convert(event.locationInWindow, from: nil))
        onPointerEvent?([], x, y)
    }

    public override func otherMouseDown(with event: NSEvent) {
        let (x, y) = translatePoint(convert(event.locationInWindow, from: nil))
        onPointerEvent?([.middle], x, y)
    }

    public override func otherMouseUp(with event: NSEvent) {
        let (x, y) = translatePoint(convert(event.locationInWindow, from: nil))
        onPointerEvent?([], x, y)
    }

    public override func scrollWheel(with event: NSEvent) {
        let (x, y) = translatePoint(convert(event.locationInWindow, from: nil))
        let mask: RFBConstants.ButtonMask = (event.scrollingDeltaY > 0) ? .scrollUp : .scrollDown
        onPointerEvent?(mask, x, y)
        onPointerEvent?([], x, y)
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

    public override func keyDown(with event: NSEvent) {
        if let keySym = mapMacKeyCode(event.keyCode, characters: event.characters) {
            onKeyEvent?(true, keySym)
        }
    }

    public override func keyUp(with event: NSEvent) {
        if let keySym = mapMacKeyCode(event.keyCode, characters: event.characters) {
            onKeyEvent?(false, keySym)
        }
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

    public init(
        remoteWidth: CGFloat,
        remoteHeight: CGFloat,
        onPointerEvent: @escaping (RFBConstants.ButtonMask, UInt16, UInt16) -> Void,
        onKeyEvent: @escaping (Bool, UInt32) -> Void
    ) {
        self.remoteWidth = remoteWidth
        self.remoteHeight = remoteHeight
        self.onPointerEvent = onPointerEvent
        self.onKeyEvent = onKeyEvent
    }

    public func makeNSView(context: Context) -> MacNativeInputView {
        let view = MacNativeInputView()
        view.remoteSize = CGSize(width: remoteWidth, height: remoteHeight)
        view.onPointerEvent = onPointerEvent
        view.onKeyEvent = onKeyEvent

        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    public func updateNSView(_ nsView: MacNativeInputView, context: Context) {
        nsView.remoteSize = CGSize(width: remoteWidth, height: remoteHeight)
        nsView.onPointerEvent = onPointerEvent
        nsView.onKeyEvent = onKeyEvent
    }
}
#endif
