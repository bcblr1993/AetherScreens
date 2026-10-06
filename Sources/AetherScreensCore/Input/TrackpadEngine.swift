import Foundation
import CoreGraphics

/// Converts point/discrete scrolling into bounded wheel ticks. Fractional motion
/// survives normal samples; oversized samples cannot create a deferred backlog.
struct NativeScrollAccumulator {
    private var remainderX: CGFloat = 0
    private var remainderY: CGFloat = 0

    mutating func consume(dx: CGFloat, dy: CGFloat, precise: Bool) -> [RFBConstants.ButtonMask] {
        consume(dx: dx, dy: dy, pointsPerTick: precise ? 10 : 1)
    }

    mutating func consume(dx: CGFloat, dy: CGFloat, pointsPerTick: CGFloat) -> [RFBConstants.ButtonMask] {
        guard dx.isFinite, dy.isFinite, pointsPerTick.isFinite, pointsPerTick > 0 else { return [] }
        func ticks(_ delta: CGFloat, remainder: inout CGFloat) -> Int {
            // Clamp before adding/converting, including CGFloat.greatestFiniteMagnitude.
            let total = remainder + min(64, max(-64, delta / pointsPerTick))
            let whole = min(64, max(-64, (abs(total) + 1e-9).rounded(.down) * (total >= 0 ? 1 : -1)))
            remainder = total - whole
            return Int(whole)
        }
        let x = ticks(dx, remainder: &remainderX)
        let y = ticks(dy, remainder: &remainderY)
        return Array(repeating: y > 0 ? .scrollUp : .scrollDown, count: abs(y))
            + Array(repeating: x > 0 ? .scrollLeft : .scrollRight, count: abs(x))
    }
}

/// Virtual Trackpad Engine that transforms touch gestures into Mac-like cursor motion and mouse events.
public final class TrackpadEngine: @unchecked Sendable {

    public enum Mode: String, CaseIterable, Identifiable, Sendable {
        case trackpad = "Trackpad"
        case touch = "Direct Touch"
        public var id: String { rawValue }
    }

    public enum HotCorner: String, CaseIterable, Identifiable, Sendable {
        case topLeft = "Top Left", topRight = "Top Right"
        case bottomLeft = "Bottom Left", bottomRight = "Bottom Right"
        public var id: String { rawValue }
        public func point(width: CGFloat, height: CGFloat) -> CGPoint {
            CGPoint(x: self == .topRight || self == .bottomRight ? max(0, width - 1) : 0,
                    y: self == .bottomLeft || self == .bottomRight ? max(0, height - 1) : 0)
        }
    }

    public var mode: Mode = .trackpad

    // Remote screen boundaries
    public var remoteWidth: CGFloat = 1920
    public var remoteHeight: CGFloat = 1080

    // Virtual cursor position on remote Mac
    public private(set) var cursorX: CGFloat = 960
    public private(set) var cursorY: CGFloat = 540

    // Mouse button state
    public enum AbsolutePointerSource: Hashable, Sendable { case mouse, pencil }
    private var touchButtons: RFBConstants.ButtonMask = []
    private var absoluteButtons: [AbsolutePointerSource: RFBConstants.ButtonMask] = [:]
    public var activeButtons: RFBConstants.ButtonMask {
        absoluteButtons.values.reduce(touchButtons) { $0.union($1) }
    }

    /// Mouse and Pencil coordinates remain absolute in both touch modes. Each
    /// source owns its buttons so cancelling one cannot release another drag.
    public func handleAbsolutePointer(point: CGPoint, viewSize: CGSize,
                                      buttons: RFBConstants.ButtonMask, source: AbsolutePointerSource) {
        guard point.x.isFinite, point.y.isFinite, viewSize.width.isFinite, viewSize.height.isFinite,
              viewSize.width > 0, viewSize.height > 0,
              remoteWidth.isFinite, remoteHeight.isFinite, remoteWidth > 0, remoteHeight > 0 else { return }
        absoluteButtons[source] = buttons.intersection([.left, .middle, .right])
        moveCursor(to: CGPoint(x: point.x / viewSize.width * remoteWidth,
                               y: point.y / viewSize.height * remoteHeight))
    }

    public func absolutePointerButtons(for source: AbsolutePointerSource) -> RFBConstants.ButtonMask {
        absoluteButtons[source] ?? []
    }

    public func releaseAbsolutePointer(_ source: AbsolutePointerSource) {
        guard let previous = absoluteButtons.removeValue(forKey: source), !previous.isEmpty else { return }
        emitPointerEvent()
    }

    // Acceleration parameters
    public var cursorSpeedMultiplier: CGFloat = 1
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

    /// Programmatic motion also updates the local cursor so the next gesture
    /// continues from the remote position in either input mode.
    public func moveCursor(to point: CGPoint) {
        func coordinate(_ value: CGFloat, extent: CGFloat) -> CGFloat {
            guard value.isFinite, extent.isFinite else { return 0 }
            return min(CGFloat(UInt16.max), max(0, min(value, max(0, extent - 1))))
        }
        cursorX = coordinate(point.x, extent: remoteWidth)
        cursorY = coordinate(point.y, extent: remoteHeight)
        emitPointerEvent()
    }

    // MARK: - Trackpad Motion & Acceleration

    /// Update cursor with finger displacement delta (dx, dy)
    public func handlePanDelta(dx: CGFloat, dy: CGFloat, coordinateScale: CGFloat = 1) {
        guard mode == .trackpad, dx.isFinite, dy.isFinite,
              coordinateScale.isFinite, coordinateScale > 0 else { return }

        // Compute velocity / magnitude
        let distance = sqrt(dx * dx + dy * dy)
        let progress = min(1, max(0, (distance - 2) / 18))
        let smooth = progress * progress * (3 - 2 * progress)
        let speed = CGFloat(RemoteDevice.validatedCursorSpeed(Double(cursorSpeedMultiplier)))
        let accel = sensitivity * speed * (1 + (accelerationFactor - 1) * smooth)

        cursorX = min(max(0, cursorX + dx * accel * coordinateScale), remoteWidth)
        cursorY = min(max(0, cursorY + dy * accel * coordinateScale), remoteHeight)

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
        click(button: .left)
    }

    /// Two-finger tap -> Right Click
    public func handleSecondaryTap() {
        click(button: .right)
    }

    public func click(button: RFBConstants.ButtonMask) {
        onPointerEvent?(activeButtons.union(button), UInt16(cursorX), UInt16(cursorY))
        onPointerEvent?(activeButtons, UInt16(cursorX), UInt16(cursorY))
    }

    /// Begin dragging (hold left button)
    public func beginDrag(button: RFBConstants.ButtonMask = .left) {
        touchButtons.formUnion(button)
        emitPointerEvent()
    }

    /// End dragging (release left button)
    public func endDrag(button: RFBConstants.ButtonMask = .left) {
        touchButtons.subtract(button)
        emitPointerEvent()
    }

    public func releaseAllButtons() {
        guard !activeButtons.isEmpty else { return }
        touchButtons = []
        absoluteButtons.removeAll()
        emitPointerEvent()
    }

    /// Two-finger scroll delta (natural scrolling)
    public func handleScroll(deltaY: CGFloat) {
        guard deltaY.isFinite, deltaY != 0 else { return }
        let mask: RFBConstants.ButtonMask = (deltaY > 0) ? .scrollUp : .scrollDown
        
        // Emit scroll wheel event
        onPointerEvent?(activeButtons.union(mask), UInt16(cursorX), UInt16(cursorY))
        
        // Immediately release wheel button mask
        onPointerEvent?(activeButtons, UInt16(cursorX), UInt16(cursorY))
    }

    public func handleHorizontalScroll(deltaX: CGFloat) {
        guard deltaX.isFinite, deltaX != 0 else { return }
        let mask: RFBConstants.ButtonMask = deltaX > 0 ? .scrollLeft : .scrollRight
        onPointerEvent?(activeButtons.union(mask), UInt16(cursorX), UInt16(cursorY))
        onPointerEvent?(activeButtons, UInt16(cursorX), UInt16(cursorY))
    }

    private func emitPointerEvent() {
        let x = UInt16(min(max(0, cursorX), remoteWidth))
        let y = UInt16(min(max(0, cursorY), remoteHeight))
        onPointerEvent?(activeButtons, x, y)
    }
}
