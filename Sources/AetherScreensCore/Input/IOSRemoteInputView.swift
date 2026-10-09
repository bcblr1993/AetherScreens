#if canImport(UIKit)
import UIKit
import SwiftUI
import Combine

/// Recognizes native touch input and moves the local cursor without rebuilding
/// the SwiftUI remote canvas for every finger sample.
struct IOSRemoteInputView: UIViewRepresentable {
    let cursorUpdates: CurrentValueSubject<RFBRemoteCursor?, Never>
    let engine: TrackpadEngine
    let canvas: CGRect
    let zoom: CGFloat
    let maximumZoom: CGFloat
    let isPanning: Bool
    let isObserveOnly: Bool
    let isFullscreen: Bool
    let onToggleFullscreen: () -> Void
    let onThreeFingerSwipe: (MacKeyMap.ThreeFingerSwipe) -> Void
    let onPan: (CGFloat, CGFloat) -> Void
    let onZoom: (CGFloat, CGPoint) -> Void
    let onKeyEvent: (Bool, UInt32) -> Void
    var onRemoteInteraction: () -> Void = {}
    var onPencilToolbarToggle: (CGPoint?) -> Void = { _ in }

    func makeUIView(context: Context) -> RemoteTouchView {
        let view = RemoteTouchView()
        view.cursorSubscription = cursorUpdates.sink { [weak view] shape in
            view?.cursor.setShape(shape)
            view?.updateCursor()
        }
        return view
    }
    func updateUIView(_ view: RemoteTouchView, context: Context) {
        if isPanning || isObserveOnly { view.releaseDrag() }
        if isObserveOnly { view.releaseHardwareKeys() }
        view.isLocalNavigation = isPanning || isObserveOnly
        view.blocksRemoteShortcuts = isObserveOnly
        view.isFullscreen = isFullscreen
        view.onToggleFullscreen = onToggleFullscreen
        view.onThreeFingerSwipe = onThreeFingerSwipe
        view.onPan = onPan
        view.engine = engine
        view.applyCanvasLayout(canvas)
        view.zoom = zoom
        view.maximumZoom = maximumZoom
        view.onZoom = onZoom
        view.onKeyEvent = onKeyEvent
        view.onRemoteInteraction = onRemoteInteraction
        view.onPencilToolbarToggle = onPencilToolbarToggle
        view.updateCursor()
        view.updateAccessibility()
    }

    static func dismantleUIView(_ view: RemoteTouchView, coordinator: ()) {
        view.releaseDrag()
        view.releaseHardwareKeys()
    }
}

final class RemoteTouchView: UIView, UIGestureRecognizerDelegate, UIPencilInteractionDelegate, UIPointerInteractionDelegate {
    var engine: TrackpadEngine? {
        didSet {
            if (oldValue == nil) != (engine == nil) { hardwarePointerInteraction.invalidate() }
        }
    }
    private var canvasProjection = ViewportProjection()
    var canvas: CGRect { canvasProjection.canvas }
    func applyCanvasLayout(_ rect: CGRect) {
        canvasProjection.applyLayout(rect)
        refreshPointerRegion()
    }
    var zoom: CGFloat = 1
    var maximumZoom: CGFloat = 4
    var onZoom: ((CGFloat, CGPoint) -> Void)?
    var onPan: ((CGFloat, CGFloat) -> Void)?
    var isLocalNavigation = false {
        didSet {
            if oldValue != isLocalNavigation { hardwarePointerInteraction.invalidate() }
        }
    }
    var blocksRemoteShortcuts = false
    var isFullscreen = false
    var onToggleFullscreen: (() -> Void)?
    var onThreeFingerSwipe: ((MacKeyMap.ThreeFingerSwipe) -> Void)?
    var onKeyEvent: ((Bool, UInt32) -> Void)?
    var onRemoteInteraction: (() -> Void)?
    var onPencilToolbarToggle: ((CGPoint?) -> Void)?
    private var hardwareKeyboard = HardwareKeyboardState()
    let cursor = RemoteCursorLayer()
    var cursorSubscription: AnyCancellable?
    private var hardwareButtons: RFBConstants.ButtonMask = []
    private var hardwarePointerVisible = false
    private var lastHardwareLocation: CGPoint?
    private var dragButton: RFBConstants.ButtonMask = []
    private var initialZoom: CGFloat = 1
    private var scrollAccumulator = ScrollWheelAccumulator()
    private var lastHoldLocation: CGPoint?
    private var accessibilityFullscreen: Bool?
    private var cachedAccessibilityLanguage: String?
    private lazy var hardwarePointerInteraction = UIPointerInteraction(delegate: self)
    private var visiblePointerRegion = CGRect.null

    override func layoutSubviews() {
        super.layoutSubviews()
        // SwiftUI can supply canvas geometry before UIView receives its new
        // bounds during rotation/resizing. Refresh after those bounds settle.
        refreshPointerRegion()
    }

    private func refreshPointerRegion() {
        let region = canvas.intersection(bounds)
        guard region != visiblePointerRegion else { return }
        visiblePointerRegion = region
        hardwarePointerInteraction.invalidate()
    }

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        addInteraction(hardwarePointerInteraction)
        let pencil = UIPencilInteraction()
        pencil.delegate = self
        addInteraction(pencil)
        accessibilityIdentifier = "remote-desktop-input"
        isAccessibilityElement = true
        updateAccessibility()
        // The tip is the remote pointer hotspot; keep it at the layer origin.
        layer.addSublayer(cursor)
        let fullscreen = UITapGestureRecognizer(target: self, action: #selector(fullscreenTapped(_:)))
        fullscreen.numberOfTouchesRequired = 2
        fullscreen.numberOfTapsRequired = 2
        fullscreen.delegate = self
        addGestureRecognizer(fullscreen)
        var threeFingerHold: UILongPressGestureRecognizer?
        for fingers in 1...3 {
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            tap.numberOfTouchesRequired = fingers
            if fingers == 2 { tap.require(toFail: fullscreen) }
            addGestureRecognizer(tap)
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
            hold.numberOfTouchesRequired = fingers
            hold.minimumPressDuration = 0.28
            hold.delegate = self
            addGestureRecognizer(hold)
            if fingers == 3 { threeFingerHold = hold }
        }
        for direction in [UISwipeGestureRecognizer.Direction.up, .down, .left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(threeFingerSwiped(_:)))
            swipe.numberOfTouchesRequired = 3
            swipe.direction = direction
            if let threeFingerHold { swipe.require(toFail: threeFingerHold) }
            addGestureRecognizer(swipe)
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
        scroll.require(toFail: fullscreen)
        addGestureRecognizer(scroll)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        pinch.require(toFail: fullscreen)
        addGestureRecognizer(pinch)
        // Finger gestures must not delay or duplicate hardware mouse clicks.
        for recognizer in gestureRecognizers ?? [] {
            recognizer.delegate = self
            recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue),
                                           NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        }
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(hardwareHovered(_:)))
        hover.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        addGestureRecognizer(hover)
        let hardwareScroll = UIPanGestureRecognizer(target: self, action: #selector(scrolled(_:)))
        hardwareScroll.allowedTouchTypes = []
        hardwareScroll.allowedScrollTypesMask = .all
        addGestureRecognizer(hardwareScroll)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        guard UIPencilInteraction.preferredTapAction != .ignore else { return }
        onPencilToolbarToggle?(nil)
    }

    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        guard UIPencilInteraction.preferredTapAction != .ignore else { return }
        onPencilToolbarToggle?(tap.hoverPose?.location)
    }

    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        guard squeeze.phase == .ended, UIPencilInteraction.preferredSqueezeAction != .ignore else { return }
        onPencilToolbarToggle?(squeeze.hoverPose?.location)
    }

    override var canBecomeFirstResponder: Bool { !blocksRemoteShortcuts }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { releaseDrag(); releaseHardwareKeys() }
        return resigned
    }

    func releaseHardwareKeys() {
        for key in hardwareKeyboard.releaseAll() { onKeyEvent?(false, key) }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard !blocksRemoteShortcuts else { super.pressesBegan(presses, with: event); return }
        var unhandled = Set<UIPress>()
        // UIPress is a set: establish modifiers before keys in the same event.
        let ordered = presses.sorted {
            let left = HardwareKeyboard.isModifier($0.key?.keyCode.rawValue ?? 0)
            let right = HardwareKeyboard.isModifier($1.key?.keyCode.rawValue ?? 0)
            return left && !right
        }
        for press in ordered {
            guard let key = press.key,
                  let symbol = hardwareKeyboard.begin(usage: key.keyCode.rawValue,
                                                       characters: key.charactersIgnoringModifiers) else {
                unhandled.insert(press); continue
            }
            onKeyEvent?(true, symbol)
        }
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }

    private func releasePresses(_ presses: Set<UIPress>) -> Set<UIPress> {
        var unhandled = Set<UIPress>()
        let ordered = presses.sorted {
            let left = HardwareKeyboard.isModifier($0.key?.keyCode.rawValue ?? 0)
            let right = HardwareKeyboard.isModifier($1.key?.keyCode.rawValue ?? 0)
            return !left && right
        }
        for press in ordered {
            guard let key = press.key, let symbol = hardwareKeyboard.end(usage: key.keyCode.rawValue) else {
                unhandled.insert(press); continue
            }
            onKeyEvent?(false, symbol)
        }
        return unhandled
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = releasePresses(presses)
        if !unhandled.isEmpty { super.pressesEnded(unhandled, with: event) }
    }
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = releasePresses(presses)
        if !unhandled.isEmpty { super.pressesCancelled(unhandled, with: event) }
    }

    override var accessibilityFrame: CGRect {
        get { UIAccessibility.convertToScreenCoordinates(canvas.intersection(bounds), in: self) }
        set { super.accessibilityFrame = newValue }
    }

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
        guard !isLocalNavigation, engine.mode == .trackpad else { return }
        let pointer = CGPoint(x: canvas.minX + engine.cursorX * canvas.width / max(1, engine.remoteWidth),
                              y: canvas.minY + engine.cursorY * canvas.height / max(1, engine.remoteHeight))
        let delta = ViewportTracking.panDelta(
            canvas: canvas, viewport: bounds, pointer: pointer,
            movement: CGSize(width: dx, height: dy))
        guard delta != .zero else { return }
        // Update the local geometry immediately, before SwiftUI supplies the
        // next viewport, so consecutive touch samples use the new origin.
        canvasProjection.pan(delta)
        refreshPointerRegion()
        onPan?(delta.width, delta.height)
    }

    @objc private func fullscreenTapped(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        releaseDrag()
        onToggleFullscreen?()
    }

    @objc private func toggleFullscreenAccessibility() -> Bool {
        releaseDrag()
        onToggleFullscreen?()
        return true
    }

    @objc private func threeFingerSwiped(_ gesture: UISwipeGestureRecognizer) {
        guard gesture.state == .ended, !blocksRemoteShortcuts, dragButton.isEmpty else { return }
        let direction: MacKeyMap.ThreeFingerSwipe
        switch gesture.direction {
        case .up: direction = .up
        case .down: direction = .down
        case .left: direction = .left
        case .right: direction = .right
        default: return
        }
        onThreeFingerSwipe?(direction)
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, !isLocalNavigation else { return }
        becomeFirstResponder()
        positionDirectly(gesture.location(in: self))
        engine?.click(button: button(for: gesture.numberOfTouchesRequired))
        updateCursor()
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        let delta = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        guard dragButton.isEmpty else { return }
        if gesture.state == .began || gesture.state == .changed {
            if isLocalNavigation { onPan?(delta.x, delta.y); return }
            if engine?.mode == .touch { positionDirectly(gesture.location(in: self)) }
            else { movePointer(dx: delta.x, dy: delta.y) }
            updateCursor()
        }
    }

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        guard !isLocalNavigation else { return }
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

    private func positionHardware(_ point: CGPoint) {
        guard !isLocalNavigation else { return }
        let movement = lastHardwareLocation.map {
            CGSize(width: point.x - $0.x, height: point.y - $0.y)
        } ?? .zero
        lastHardwareLocation = point
        let delta = ViewportTracking.panDelta(canvas: canvas, viewport: bounds,
            pointer: point, movement: movement)
        if delta != .zero {
            canvasProjection.pan(delta)
            refreshPointerRegion()
            onPan?(delta.width, delta.height)
        }
        // Map after panning so the remote pointer remains beneath the physical pointer.
        engine?.handleAbsolutePointer(
            point: CGPoint(x: point.x - canvas.minX, y: point.y - canvas.minY), viewSize: canvas.size)
        updateCursor()
    }

    @objc private func hardwareHovered(_ gesture: UIHoverGestureRecognizer) {
        if gesture.state == .began || gesture.state == .changed { onRemoteInteraction?() }
        hardwarePointerVisible = gesture.state == .began || gesture.state == .changed
        if hardwarePointerVisible && !isLocalNavigation { positionHardware(gesture.location(in: self)) }
        else { lastHardwareLocation = nil; updateCursor() }
    }

    func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
        // RemoteCursorLayer renders the server cursor (or default arrow). Avoid
        // drawing UIKit's system pointer on top of it during remote control.
        engine != nil && !isLocalNavigation ? .hidden() : nil
    }

    func pointerInteraction(_ interaction: UIPointerInteraction, regionFor request: UIPointerRegionRequest,
                            defaultRegion: UIPointerRegion) -> UIPointerRegion? {
        guard engine != nil, !isLocalNavigation else { return nil }
        let visibleCanvas = canvas.intersection(bounds)
        guard !visibleCanvas.isEmpty, visibleCanvas.contains(request.location) else { return nil }
        return UIPointerRegion(rect: visibleCanvas, identifier: "remote-screen" as NSString)
    }

    private func updateHardwareTouch(_ touches: Set<UITouch>, event: UIEvent?, cancelled: Bool) {
        guard let touch = touches.first(where: { $0.type == .indirectPointer }) else { return }
        guard !isLocalNavigation else { releaseDrag(); return }
        // A cancelled touch only releases ownership. Its terminal location
        // must not drag the remote pointer or trigger viewport edge following.
        if !cancelled {
            // Move with held buttons before publishing button transitions.
            positionHardware(touch.location(in: self))
        } else {
            lastHardwareLocation = nil
        }
        var buttons: RFBConstants.ButtonMask = []
        if !cancelled, let mask = event?.buttonMask {
            if mask.contains(.primary) { buttons.insert(.left) }
            if mask.contains(.secondary) { buttons.insert(.right) }
            if mask.rawValue & 4 != 0 { buttons.insert(.middle) }
        }
        let released = hardwareButtons.subtracting(buttons)
        let pressed = buttons.subtracting(hardwareButtons)
        if !released.isEmpty { engine?.endDrag(button: released) }
        if !pressed.isEmpty { engine?.beginDrag(button: pressed) }
        hardwareButtons = buttons
        updateCursor()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        onRemoteInteraction?()
        if !blocksRemoteShortcuts { becomeFirstResponder() }
        updateHardwareTouch(touches, event: event, cancelled: false)
        super.touchesBegan(touches, with: event)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        updateHardwareTouch(touches, event: event, cancelled: false)
        super.touchesMoved(touches, with: event)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        updateHardwareTouch(touches, event: event, cancelled: false)
        super.touchesEnded(touches, with: event)
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        updateHardwareTouch(touches, event: event, cancelled: true)
        super.touchesCancelled(touches, with: event)
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { releaseDrag(); releaseHardwareKeys() }
    }

    func releaseDrag() {
        // Clear local ownership before callbacks can synchronously change focus.
        // Release the complete chord once, without intermediate held buttons.
        hardwareButtons = []
        dragButton = []
        lastHardwareLocation = nil
        lastHoldLocation = nil
        engine?.releaseAllButtons()
        updateCursor()
    }

    @objc private func scrolled(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began { scrollAccumulator = ScrollWheelAccumulator(); onRemoteInteraction?() }
        let delta = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        guard dragButton.isEmpty else { return }
        guard gesture.state == .began || gesture.state == .changed else { return }
        if isLocalNavigation { onPan?(delta.x, delta.y); return }
        // Bound each gesture callback while retaining the existing eight-point
        // wheel step and fractional movement between callbacks.
        for mask in scrollAccumulator.consume(dx: delta.x, dy: delta.y, precise: true, preciseDivisor: 8) {
            switch mask {
            case .scrollUp: engine?.handleScroll(deltaY: 8)
            case .scrollDown: engine?.handleScroll(deltaY: -8)
            case .scrollLeft: engine?.handleHorizontalScroll(deltaX: 8)
            case .scrollRight: engine?.handleHorizontalScroll(deltaX: -8)
            default: break
            }
        }
    }

    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began { initialZoom = zoom; releaseDrag() }
        if gesture.state == .began || gesture.state == .changed {
            onZoom?(max(1, min(maximumZoom, initialZoom * gesture.scale)), gesture.location(in: self))
        }
    }

    override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        !(isLocalNavigation && gesture is UILongPressGestureRecognizer)
    }

    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        onRemoteInteraction?()
        return true
    }

    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // A held mouse button must continue moving while its pan recognizer runs.
        gesture is UILongPressGestureRecognizer || other is UILongPressGestureRecognizer
    }

    func updateCursor() {
        guard let engine else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let heldButtons = dragButton.union(hardwareButtons)
        cursor.isHidden = isLocalNavigation || (engine.mode != .trackpad && heldButtons.isEmpty && !hardwarePointerVisible)
        cursor.position = CGPoint(x: canvas.minX + engine.cursorX * canvas.width / max(1, engine.remoteWidth),
                                  y: canvas.minY + engine.cursorY * canvas.height / max(1, engine.remoteHeight))
        let color: UIColor = heldButtons.contains(.right) ? .systemRed : heldButtons.contains(.middle) ? .systemGreen : heldButtons.isEmpty ? .white : .systemBlue
        cursor.fallback.fillColor = color.cgColor
        CATransaction.commit()
    }

    func updateAccessibility() {
        let language = AppLocalization.language
        let identifier = AppLocalization.identifier(for: language)
        guard accessibilityFullscreen != isFullscreen || cachedAccessibilityLanguage != identifier else { return }
        accessibilityFullscreen = isFullscreen
        cachedAccessibilityLanguage = identifier
        accessibilityLabel = AppLocalization.string("Remote desktop canvas", language: language)
        accessibilityValue = isFullscreen ? AppLocalization.string("Full Screen", language: language) : nil
        accessibilityCustomActions = [UIAccessibilityCustomAction(
            name: AppLocalization.string(isFullscreen ? "Exit Full Screen" : "Enter Full Screen", language: language),
            target: self, selector: #selector(toggleFullscreenAccessibility))]
    }
}
#endif
