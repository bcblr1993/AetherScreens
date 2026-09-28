import Foundation
import CoreGraphics

/// Virtual Trackpad Engine that transforms touch gestures into Mac-like cursor motion and mouse events.
public final class TrackpadEngine: @unchecked Sendable {

    public enum Mode: String, CaseIterable, Identifiable, Sendable {
        case trackpad = "Trackpad"
        case touch = "Direct Touch"
        public var id: String { rawValue }
    }

    public var mode: Mode = .trackpad

    // Remote screen boundaries
    public var remoteWidth: CGFloat = 1920
    public var remoteHeight: CGFloat = 1080

    // Virtual cursor position on remote Mac
    public private(set) var cursorX: CGFloat = 960
    public private(set) var cursorY: CGFloat = 540

    // Mouse button state
    public private(set) var activeButtons: RFBConstants.ButtonMask = []

    // Acceleration parameters
    public var sensitivity: CGFloat = 1.2
    public var accelerationFactor: CGFloat = 1.8

    // Event callbacks
    public var onPointerEvent: (@Sendable (RFBConstants.ButtonMask, UInt16, UInt16) -> Void)?

    public init(remoteWidth: CGFloat = 1920, remoteHeight: CGFloat = 1080) {
        self.remoteWidth = remoteWidth
        self.remoteHeight = remoteHeight
        self.cursorX = remoteWidth / 2
        self.cursorY = remoteHeight / 2
    }

    /// Reset cursor to center of remote display
    public func resetCursor() {
        cursorX = remoteWidth / 2
        cursorY = remoteHeight / 2
        emitPointerEvent()
    }

    // MARK: - Trackpad Motion & Acceleration

    /// Update cursor with finger displacement delta (dx, dy)
    public func handlePanDelta(dx: CGFloat, dy: CGFloat) {
        guard mode == .trackpad else { return }

        // Compute velocity / magnitude
        let distance = sqrt(dx * dx + dy * dy)
        let accel: CGFloat
        if distance > 15 {
            accel = sensitivity * accelerationFactor
        } else if distance > 5 {
            accel = sensitivity * 1.3
        } else {
            accel = sensitivity * 1.0
        }

        cursorX = min(max(0, cursorX + dx * accel), remoteWidth)
        cursorY = min(max(0, cursorY + dy * accel), remoteHeight)

        emitPointerEvent()
    }

    /// Direct touch mode mapping (view point -> remote point)
    public func handleDirectTouch(point: CGPoint, viewSize: CGSize) {
        guard mode == .touch, viewSize.width > 0, viewSize.height > 0 else { return }

        let scaleX = remoteWidth / viewSize.width
        let scaleY = remoteHeight / viewSize.height

        cursorX = min(max(0, point.x * scaleX), remoteWidth)
        cursorY = min(max(0, point.y * scaleY), remoteHeight)

        emitPointerEvent()
    }

    // MARK: - Mouse Button Actions

    /// Single tap -> Left Click (press and release)
    public func handleTap() {
        activeButtons.insert(.left)
        emitPointerEvent()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }
            self.activeButtons.remove(.left)
            self.emitPointerEvent()
        }
    }

    /// Two-finger tap -> Right Click
    public func handleSecondaryTap() {
        activeButtons.insert(.right)
        emitPointerEvent()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }
            self.activeButtons.remove(.right)
            self.emitPointerEvent()
        }
    }

    /// Begin dragging (hold left button)
    public func beginDrag() {
        activeButtons.insert(.left)
        emitPointerEvent()
    }

    /// End dragging (release left button)
    public func endDrag() {
        activeButtons.remove(.left)
        emitPointerEvent()
    }

    /// Two-finger scroll delta (natural scrolling)
    public func handleScroll(deltaY: CGFloat) {
        let mask: RFBConstants.ButtonMask = (deltaY > 0) ? .scrollUp : .scrollDown
        
        // Emit scroll wheel event
        onPointerEvent?(mask, UInt16(cursorX), UInt16(cursorY))
        
        // Immediately release wheel button mask
        onPointerEvent?([], UInt16(cursorX), UInt16(cursorY))
    }

    private func emitPointerEvent() {
        let x = UInt16(min(max(0, cursorX), remoteWidth))
        let y = UInt16(min(max(0, cursorY), remoteHeight))
        onPointerEvent?(activeButtons, x, y)
    }
}
