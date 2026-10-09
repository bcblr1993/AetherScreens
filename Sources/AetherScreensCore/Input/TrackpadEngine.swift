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
    public func handlePanDelta(dx: CGFloat, dy: CGFloat, coordinateScale: CGFloat = 1) {
        guard mode == .trackpad else { return }

        // Compute velocity / magnitude
        let distance = sqrt(dx * dx + dy * dy)
        let progress = min(1, max(0, (distance - 2) / 18))
        let smooth = progress * progress * (3 - 2 * progress)
        let accel = sensitivity * (1 + (accelerationFactor - 1) * smooth)

        cursorX = min(max(0, cursorX + dx * accel * coordinateScale), remoteWidth)
        cursorY = min(max(0, cursorY + dy * accel * coordinateScale), remoteHeight)

        emitPointerEvent()
    }

    /// Direct touch mode mapping (view point -> remote point)
    public func handleDirectTouch(point: CGPoint, viewSize: CGSize) {
        guard mode == .touch else { return }
        handleAbsolutePointer(point: point, viewSize: viewSize)
    }

    /// Hardware pointers use absolute canvas coordinates in either finger mode.
    public func handleAbsolutePointer(point: CGPoint, viewSize: CGSize) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }

        let scaleX = remoteWidth / viewSize.width
        let scaleY = remoteHeight / viewSize.height

        cursorX = min(max(0, point.x * scaleX), remoteWidth)
        cursorY = min(max(0, point.y * scaleY), remoteHeight)

        emitPointerEvent()
    }

    // MARK: - Mouse Button Actions

    /// Single tap -> Left Click (press and release)
    public func handleTap() {
        click(button: .left)
    }

    /// Two-finger tap -> Right Click
    public func handleSecondaryTap() {
        click(button: .right)
    }

    public func click(button: RFBConstants.ButtonMask) {
        onPointerEvent?(activeButtons.union(button), pointerCoordinate(cursorX, dimension: remoteWidth), pointerCoordinate(cursorY, dimension: remoteHeight))
        onPointerEvent?(activeButtons, pointerCoordinate(cursorX, dimension: remoteWidth), pointerCoordinate(cursorY, dimension: remoteHeight))
    }

    /// Begin dragging (hold left button)
    public func beginDrag(button: RFBConstants.ButtonMask = .left) {
        activeButtons.formUnion(button)
        emitPointerEvent()
    }

    /// End dragging (release left button)
    public func endDrag(button: RFBConstants.ButtonMask = .left) {
        activeButtons.subtract(button)
        emitPointerEvent()
    }

    public func releaseAllButtons() {
        guard !activeButtons.isEmpty else { return }
        activeButtons = []
        emitPointerEvent()
    }

    /// Two-finger scroll delta (natural scrolling)
    public func handleScroll(deltaY: CGFloat) {
        guard deltaY != 0 else { return }
        let mask: RFBConstants.ButtonMask = (deltaY > 0) ? .scrollUp : .scrollDown
        
        // Emit scroll wheel event
        onPointerEvent?(activeButtons.union(mask), pointerCoordinate(cursorX, dimension: remoteWidth), pointerCoordinate(cursorY, dimension: remoteHeight))
        
        // Immediately release wheel button mask
        onPointerEvent?(activeButtons, pointerCoordinate(cursorX, dimension: remoteWidth), pointerCoordinate(cursorY, dimension: remoteHeight))
    }

    public func handleHorizontalScroll(deltaX: CGFloat) {
        guard deltaX != 0 else { return }
        let mask: RFBConstants.ButtonMask = deltaX > 0 ? .scrollLeft : .scrollRight
        onPointerEvent?(activeButtons.union(mask), pointerCoordinate(cursorX, dimension: remoteWidth), pointerCoordinate(cursorY, dimension: remoteHeight))
        onPointerEvent?(activeButtons, pointerCoordinate(cursorX, dimension: remoteWidth), pointerCoordinate(cursorY, dimension: remoteHeight))
    }

    // RFB coordinates address pixels, so the last pixel is dimension - 1.
    // Invalid geometry must never trap while converting to the wire's UInt16.
    private func pointerCoordinate(_ value: CGFloat, dimension: CGFloat) -> UInt16 {
        guard value.isFinite, dimension.isFinite, dimension > 0 else { return 0 }
        let maximum = min(CGFloat(UInt16.max), max(0, dimension - 1))
        return UInt16(min(max(0, value), maximum))
    }

    private func emitPointerEvent() {
        let x = pointerCoordinate(cursorX, dimension: remoteWidth)
        let y = pointerCoordinate(cursorY, dimension: remoteHeight)
        onPointerEvent?(activeButtons, x, y)
    }
}
