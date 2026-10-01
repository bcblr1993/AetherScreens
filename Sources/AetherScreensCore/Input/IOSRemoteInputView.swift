#if canImport(UIKit)
import UIKit
import SwiftUI

/// Recognizes native touch input and moves the local cursor without rebuilding
/// the SwiftUI remote canvas for every finger sample.
struct IOSRemoteInputView: UIViewRepresentable {
    let engine: TrackpadEngine
    let canvas: CGRect
    let zoom: CGFloat
    let onZoom: (CGFloat) -> Void

    func makeUIView(context: Context) -> RemoteTouchView { RemoteTouchView() }
    func updateUIView(_ view: RemoteTouchView, context: Context) {
        view.engine = engine
        view.canvas = canvas
        view.zoom = zoom
        view.onZoom = onZoom
        view.updateCursor()
    }

    static func dismantleUIView(_ view: RemoteTouchView, coordinator: ()) { view.releaseDrag() }
}

final class RemoteTouchView: UIView, UIGestureRecognizerDelegate {
    var engine: TrackpadEngine?
    var canvas = CGRect.zero
    var zoom: CGFloat = 1
    var onZoom: ((CGFloat) -> Void)?
    private let cursor = CAShapeLayer()
    private var dragButton: RFBConstants.ButtonMask = []
    private var initialZoom: CGFloat = 1
    private var scrollRemainder = CGPoint.zero
    private var lastHoldLocation: CGPoint?

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        accessibilityIdentifier = "remote-desktop-input"
        cursor.path = UIBezierPath(ovalIn: CGRect(x: -7, y: -7, width: 14, height: 14)).cgPath
        cursor.fillColor = UIColor.white.cgColor
        cursor.strokeColor = UIColor.black.cgColor
        cursor.lineWidth = 1.5
        layer.addSublayer(cursor)
        for fingers in 1...3 {
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            tap.numberOfTouchesRequired = fingers
            addGestureRecognizer(tap)
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
            hold.numberOfTouchesRequired = fingers
            hold.minimumPressDuration = 0.28
            hold.delegate = self
            addGestureRecognizer(hold)
        }
        let pointer = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pointer.minimumNumberOfTouches = 1
        pointer.maximumNumberOfTouches = 1
        pointer.delegate = self
        addGestureRecognizer(pointer)
        let scroll = UIPanGestureRecognizer(target: self, action: #selector(scrolled(_:)))
        scroll.minimumNumberOfTouches = 2
        scroll.maximumNumberOfTouches = 2
        scroll.delegate = self
        addGestureRecognizer(scroll)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        addGestureRecognizer(pinch)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    private func button(for fingers: Int) -> RFBConstants.ButtonMask {
        fingers == 2 ? .right : fingers == 3 ? .middle : .left
    }

    private func positionDirectly(_ point: CGPoint) {
        guard let engine, engine.mode == .touch else { return }
        engine.handleDirectTouch(point: CGPoint(x: point.x - canvas.minX, y: point.y - canvas.minY), viewSize: canvas.size)
    }

    private func movePointer(dx: CGFloat, dy: CGFloat) {
        guard let engine, canvas.width > 0 else { return }
        // Finger translation is measured in screen points, not remote pixels.
        engine.handlePanDelta(dx: dx, dy: dy, coordinateScale: engine.remoteWidth / canvas.width)
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        positionDirectly(gesture.location(in: self))
        engine?.click(button: button(for: gesture.numberOfTouchesRequired))
        updateCursor()
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        let delta = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        guard dragButton.isEmpty else { return }
        if gesture.state == .began || gesture.state == .changed {
            if engine?.mode == .touch { positionDirectly(gesture.location(in: self)) }
            else { movePointer(dx: delta.x, dy: delta.y) }
            updateCursor()
        }
    }

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            positionDirectly(gesture.location(in: self))
            dragButton = button(for: gesture.numberOfTouchesRequired)
            lastHoldLocation = gesture.location(in: self)
            engine?.beginDrag(button: dragButton)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else if gesture.state == .changed {
            let point = gesture.location(in: self)
            if engine?.mode == .touch { positionDirectly(point) }
            else if let last = lastHoldLocation { movePointer(dx: point.x - last.x, dy: point.y - last.y) }
            lastHoldLocation = point
        } else if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
            releaseDrag()
        }
        updateCursor()
    }

    func releaseDrag() {
        if !dragButton.isEmpty { engine?.endDrag(button: dragButton); dragButton = [] }
        lastHoldLocation = nil
    }

    @objc private func scrolled(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began { scrollRemainder = .zero }
        let delta = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        guard dragButton.isEmpty else { return }
        guard gesture.state == .began || gesture.state == .changed else { return }
        scrollRemainder.x += delta.x
        scrollRemainder.y += delta.y
        // RFB wheel events are discrete; retain sub-step movement between samples.
        while abs(scrollRemainder.y) >= 8 {
            let step: CGFloat = scrollRemainder.y > 0 ? 8 : -8
            engine?.handleScroll(deltaY: step)
            scrollRemainder.y -= step
        }
        while abs(scrollRemainder.x) >= 8 {
            let step: CGFloat = scrollRemainder.x > 0 ? 8 : -8
            engine?.handleHorizontalScroll(deltaX: step)
            scrollRemainder.x -= step
        }
    }

    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began { initialZoom = zoom; releaseDrag() }
        if gesture.state == .began || gesture.state == .changed { onZoom?(max(1, min(4, initialZoom * gesture.scale))) }
    }

    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // A held mouse button must continue moving while its pan recognizer runs.
        gesture is UILongPressGestureRecognizer || other is UILongPressGestureRecognizer
    }

    func updateCursor() {
        guard let engine else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursor.isHidden = engine.mode != .trackpad
        cursor.position = CGPoint(x: canvas.minX + engine.cursorX * canvas.width / max(1, engine.remoteWidth),
                                  y: canvas.minY + engine.cursorY * canvas.height / max(1, engine.remoteHeight))
        cursor.fillColor = dragButton.isEmpty ? UIColor.white.cgColor : UIColor.systemBlue.cgColor
        CATransaction.commit()
    }
}
#endif
