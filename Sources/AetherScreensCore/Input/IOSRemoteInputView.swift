#if canImport(UIKit)
import UIKit
import SwiftUI

/// Recognizes native touch input and moves the local cursor without rebuilding
/// the SwiftUI remote canvas for every finger sample.
struct IOSRemoteInputView: UIViewRepresentable {
    let engine: TrackpadEngine
    let inputDiagnosticIdentifier: UUID
    let canvas: CGRect
    let zoom: CGFloat
    let isPanning: Bool
    let isObserveOnly: Bool
    let isFullscreen: Bool
    let onToggleFullscreen: () -> Void
    let onThreeFingerSwipe: (MacKeyMap.ThreeFingerSwipe) -> Void
    let hardwareKeyboardConfiguration: HardwareKeyboardConfiguration
    let hardwareKeyboardEnabled: Bool
    let onHardwareKey: (Bool, UInt32) -> Void
    let onPencilGesture: (PencilGesture, CGPoint?, CGSize?) -> Void
    let boundaryGesturesEnabled: Bool
    let onScreenBoundary: (ScreenBoundaryTarget) -> Void
    let onPan: (CGFloat, CGFloat) -> Void
    let onZoom: (CGFloat) -> Void

    func makeUIView(context: Context) -> RemoteTouchView { RemoteTouchView() }
    func updateUIView(_ view: RemoteTouchView, context: Context) {
        if (isPanning || isObserveOnly) && !view.isLocalNavigation { view.releaseAllInput() }
        if let previous = view.engine, previous !== engine { view.releaseAllInput() }
        view.isLocalNavigation = isPanning || isObserveOnly
        view.blocksRemoteShortcuts = isObserveOnly
        view.isFullscreen = isFullscreen
        view.onToggleFullscreen = onToggleFullscreen
        view.onThreeFingerSwipe = onThreeFingerSwipe
        view.keyboard.configuration = hardwareKeyboardConfiguration
        view.keyboard.onKeyEvent = onHardwareKey
        view.hardwareKeyboardEnabled = hardwareKeyboardEnabled
        view.onPencilGesture = onPencilGesture
        view.boundaryGesturesEnabled = boundaryGesturesEnabled
        view.onScreenBoundary = onScreenBoundary
        view.onPan = onPan
        view.engine = engine
        view.inputDiagnosticIdentifier = inputDiagnosticIdentifier
        view.canvas = canvas
        view.zoom = zoom
        view.onZoom = onZoom
        view.updateCursor()
    }

    static func dismantleUIView(_ view: RemoteTouchView, coordinator: ()) {
        view.detachBoundaryGestures()
        view.releaseAllInput()
    }
}

final class RemoteTouchView: UIView, UIGestureRecognizerDelegate, UIPencilInteractionDelegate {
    var inputDiagnosticIdentifier: UUID?
    var boundaryGesturesEnabled = false
    var onScreenBoundary: ((ScreenBoundaryTarget) -> Void)?
    private var boundaryGestures: [UIScreenEdgePanGestureRecognizer] = []
    private var boundaryTouchOrigins: [ObjectIdentifier: CGPoint] = [:]
    private var lastBoundaryDispatch: TimeInterval = -.infinity

    override func didMoveToWindow() {
        super.didMoveToWindow()
        detachBoundaryGestures()
        guard let window else { return }
        // Window-level recognition also covers the bottom shortcuts toolbar.
        // Delegate gates keep it restricted to the active remote session.
        for edge in [UIRectEdge.left, .right, .top, .bottom] {
            let gesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(boundarySwiped(_:)))
            gesture.edges = edge
            gesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            gesture.delegate = self
            window.addGestureRecognizer(gesture)
            boundaryGestures.append(gesture)
        }
        recordBoundaryDiagnostics(stage: "attached", gesture: nil)
    }
    func detachBoundaryGestures() {
        for gesture in boundaryGestures { gesture.view?.removeGestureRecognizer(gesture) }
        boundaryGestures.removeAll()
        boundaryTouchOrigins.removeAll()
    }
    private var isInFrontmostPresentation: Bool {
        guard let window, var controller = window.rootViewController else { return false }
        while let presented = controller.presentedViewController {
            controller = presented
        }
        // The remote session is itself a full-screen presentation. Allow its
        // canvas, but reject a sheet or alert presented above that session.
        guard let visibleView = controller.viewIfLoaded else { return false }
        return isDescendant(of: visibleView)
    }
    private func recordBoundaryDiagnostics(stage: String, gesture: UIScreenEdgePanGestureRecognizer?) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_DIAGNOSTICS"] == "1" else { return }
        var state: [String: Any] = [
            "stage": stage, "attachedRecognizers": boundaryGestures.count,
            "enabled": boundaryGesturesEnabled, "localNavigation": isLocalNavigation,
            "foreground": UIApplication.shared.applicationState == .active,
            "frontmostPresentation": isInFrontmostPresentation
        ]
        if let gesture, let window {
            let translation = gesture.translation(in: window), location = gesture.location(in: window)
            let velocity = gesture.velocity(in: window)
            state["translationX"] = translation.x; state["translationY"] = translation.y
            state["velocityX"] = velocity.x; state["velocityY"] = velocity.y
            state["locationX"] = location.x; state["locationY"] = location.y
            state["edges"] = gesture.edges.rawValue; state["recognizerState"] = gesture.state.rawValue
            if let origin = boundaryTouchOrigins[ObjectIdentifier(gesture)] {
                state["touchOriginX"] = origin.x; state["touchOriginY"] = origin.y
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]),
           let value = String(data: data, encoding: .utf8) {
            boundaryDiagnosticValue = value
            accessibilityValue = value
        }
        #endif
    }

    #if DEBUG
    private var boundaryDiagnosticValue: String?
    #endif
    @objc private func boundarySwiped(_ gesture: UIScreenEdgePanGestureRecognizer) {
        recordBoundaryDiagnostics(stage: "action", gesture: gesture)
        defer {
            if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                boundaryTouchOrigins.removeValue(forKey: ObjectIdentifier(gesture))
            }
        }
        guard gesture.state == .ended, boundaryGesturesEnabled, !isLocalNavigation,
              UIApplication.shared.applicationState == .active, let window,
              isInFrontmostPresentation,
              let origin = boundaryTouchOrigins[ObjectIdentifier(gesture)] else { return }
        let location = gesture.location(in: window)
        // UIKit resets pan translation at recognition, after system-edge
        // arbitration may already have consumed part of the inward travel.
        // Classify against the original contact rather than that reset origin.
        let delta = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
        guard let target = ScreenBoundaryGesture.target(
            start: origin,
            translation: delta, size: window.bounds.size) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastBoundaryDispatch > 0.15 else { return }
        lastBoundaryDispatch = now
        releaseAllInput()
        onScreenBoundary?(target)
        updateCursor()
    }

    private var keyRepeatTimer: Timer?
    let keyboard = HardwareKeyboardState()

    private func stopKeyRepeat() {
        keyRepeatTimer?.invalidate()
        keyRepeatTimer = nil
    }
    @objc private func advanceKeyRepeat() {
        guard hardwareKeyboardEnabled, isFirstResponder,
              UIApplication.shared.applicationState == .active, keyboard.hasRepeatCandidate else {
            stopKeyRepeat()
            return
        }
        keyboard.advanceRepeat(at: ProcessInfo.processInfo.systemUptime)
    }
    private func updateKeyRepeat() {
        guard keyboard.hasRepeatCandidate else { stopKeyRepeat(); return }
        guard keyRepeatTimer == nil else { return }
        let timer = Timer(timeInterval: 0.01, target: self, selector: #selector(advanceKeyRepeat), userInfo: nil, repeats: true)
        timer.tolerance = 0.005
        RunLoop.main.add(timer, forMode: .common)
        keyRepeatTimer = timer
    }
    var hardwareKeyboardEnabled = false {
        didSet { if !hardwareKeyboardEnabled { keyboard.releaseAll(); resignFirstResponder() } }
    }
    override var canBecomeFirstResponder: Bool { hardwareKeyboardEnabled }
    override func resignFirstResponder() -> Bool {
        stopKeyRepeat()
        keyboard.releaseAll()
        return super.resignFirstResponder()
    }

    private func handlePresses(_ presses: Set<UIPress>, ending: Bool) -> Set<UIPress> {
        guard hardwareKeyboardEnabled, UIApplication.shared.applicationState == .active else { return presses }
        var remaining = presses
        let ordered = presses.sorted {
            let left = HardwareKeyboardState.isModifier(Int($0.key?.keyCode.rawValue ?? 0))
            let right = HardwareKeyboardState.isModifier(Int($1.key?.keyCode.rawValue ?? 0))
            return ending ? (!left && right) : (left && !right)
        }
        for press in ordered {
            guard let key = press.key else { continue }
            let usage = Int(key.keyCode.rawValue)
            let shortcut = !key.modifierFlags.intersection([.command, .control, .alternate]).isEmpty
            let handled = ending ? keyboard.release(usage: usage) : keyboard.press(
                usage: usage, characters: shortcut ? key.charactersIgnoringModifiers : key.characters)
            if handled { remaining.remove(press) }
        }
        updateKeyRepeat()
        return remaining
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let remaining = handlePresses(presses, ending: false)
        if !remaining.isEmpty { super.pressesBegan(remaining, with: event) }
    }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let remaining = handlePresses(presses, ending: true)
        if !remaining.isEmpty { super.pressesEnded(remaining, with: event) }
    }
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let remaining = handlePresses(presses, ending: true)
        if !remaining.isEmpty { super.pressesCancelled(remaining, with: event) }
    }

    var engine: TrackpadEngine?
    var canvas = CGRect.zero
    var zoom: CGFloat = 1
    var onZoom: ((CGFloat) -> Void)?
    var onPan: ((CGFloat, CGFloat) -> Void)?
    var isLocalNavigation = false
    var blocksRemoteShortcuts = false
    var isFullscreen = false
    var onToggleFullscreen: (() -> Void)?
    var onThreeFingerSwipe: ((MacKeyMap.ThreeFingerSwipe) -> Void)?
    var onPencilGesture: ((PencilGesture, CGPoint?, CGSize?) -> Void)?
    private let cursor = CAShapeLayer()
    private var dragButton: RFBConstants.ButtonMask = []
    private var initialZoom: CGFloat = 1
    private var pinchRecognizer: UIPinchGestureRecognizer?
    private var isPinching: Bool {
        pinchRecognizer?.state == .began || pinchRecognizer?.state == .changed
    }
    private var scrollAccumulator = NativeScrollAccumulator()
    private var lastHoldLocation: CGPoint?
    private var lastNativeNavigationLocations: [TrackpadEngine.AbsolutePointerSource: CGPoint] = [:]
    private var nativePointerVisible = false
    private var pencilHovering = false
    private var hardwareScrollAccumulator = NativeScrollAccumulator()

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        accessibilityIdentifier = "remote-desktop-input"
        isAccessibilityElement = true
        accessibilityLabel = AppLocalization.string("Remote desktop canvas")
        // The tip, rather than the center of an opaque disc, marks the click.
        // Keep its size in screen points regardless of desktop zoom.
        let arrow = UIBezierPath()
        arrow.move(to: .zero)
        for point in [CGPoint(x: 0, y: 16), CGPoint(x: 4, y: 12),
                      CGPoint(x: 7, y: 18), CGPoint(x: 10, y: 16),
                      CGPoint(x: 7, y: 10), CGPoint(x: 13, y: 10)] {
            arrow.addLine(to: point)
        }
        arrow.close()
        cursor.path = arrow.cgPath
        cursor.fillColor = UIColor.white.cgColor
        cursor.strokeColor = UIColor.black.cgColor
        cursor.lineWidth = 1
        cursor.lineJoin = .round
        layer.addSublayer(cursor)
        let fullscreen = UITapGestureRecognizer(target: self, action: #selector(fullscreenTapped(_:)))
        fullscreen.numberOfTouchesRequired = 2
        fullscreen.numberOfTapsRequired = 2
        fullscreen.delegate = self
        addGestureRecognizer(fullscreen)
        // Each completed one-finger tap emits one immediate click. A separate
        // double-tap recognizer would add a third click to the completed pair.
        var threeFingerHold: UILongPressGestureRecognizer?
        for fingers in 1...3 {
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            tap.numberOfTouchesRequired = fingers
            if fingers == 2 { tap.require(toFail: fullscreen) }
            addGestureRecognizer(tap)
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
            hold.numberOfTouchesRequired = fingers
            hold.minimumPressDuration = 0.28
            // A two-finger double tap is local fullscreen navigation. Wait for
            // it to fail before starting a right-button drag from the same touch.
            if fingers == 2 { hold.require(toFail: fullscreen) }
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
        // A pinch must start as soon as the finger distance changes. Waiting
        // for the two-finger double tap can let a stationary-centroid hold
        // become a right-button drag during an inward pinch.
        pinchRecognizer = pinch
        addGestureRecognizer(pinch)
        // Finger recognizers must not reinterpret mouse/Pencil events as taps
        // or delayed long presses. Those devices deliver immediate absolute input.
        for recognizer in gestureRecognizers ?? [] {
            recognizer.delegate = self
            recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        }
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(nativeHovered(_:)))
        hover.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        addGestureRecognizer(hover)
        let pencilHover = UIHoverGestureRecognizer(target: self, action: #selector(pencilHovered(_:)))
        pencilHover.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        addGestureRecognizer(pencilHover)
        let hardwareScroll = UIPanGestureRecognizer(target: self, action: #selector(hardwareScrolled(_:)))
        hardwareScroll.allowedScrollTypesMask = .all
        hardwareScroll.allowedTouchTypes = []
        hardwareScroll.cancelsTouchesInView = false
        addGestureRecognizer(hardwareScroll)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationInputPaused),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        let pencil = UIPencilInteraction()
        pencil.delegate = self
        addInteraction(pencil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func applicationInputPaused() {
        releaseAllInput()
        resignFirstResponder()
    }

    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        guard UIPencilInteraction.preferredTapAction != .ignore else { return }
        onPencilGesture?(.doubleTap, nil, nil)
        updateCursor()
    }

    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        // UIKit calls only this delegate method on newer systems, avoiding a
        // duplicate action when the legacy method is also implemented.
        guard UIPencilInteraction.preferredTapAction != .ignore else { return }
        dispatchPencilGesture(.doubleTap, hoverLocation: tap.hoverPose?.location)
    }

    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        guard squeeze.phase == .ended, UIPencilInteraction.preferredSqueezeAction != .ignore else { return }
        dispatchPencilGesture(.squeeze, hoverLocation: squeeze.hoverPose?.location)
    }

    private func dispatchPencilGesture(_ gesture: PencilGesture, hoverLocation: CGPoint?) {
        if let point = hoverLocation {
            // The model validates the desktop bounds for clicks while still
            // allowing local toolbar gestures outside the desktop.
            onPencilGesture?(gesture, CGPoint(x: point.x - canvas.minX, y: point.y - canvas.minY), canvas.size)
        } else {
            onPencilGesture?(gesture, nil, nil)
        }
        updateCursor()
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

    @objc private func nativeHovered(_ gesture: UIHoverGestureRecognizer) {
        nativePointerVisible = gesture.state == .began || gesture.state == .changed
        guard nativePointerVisible, !isLocalNavigation, canvas.contains(gesture.location(in: self)) else { updateCursor(); return }
        let point = gesture.location(in: self)
        // Hover never changes held buttons. Pencil and mouse contacts are handled
        // separately below; hover only supplies the location.
        engine?.moveCursor(to: CGPoint(x: (point.x - canvas.minX) / max(1, canvas.width) * (engine?.remoteWidth ?? 0),
                                      y: (point.y - canvas.minY) / max(1, canvas.height) * (engine?.remoteHeight ?? 0)))
        updateCursor()
    }

    @objc private func pencilHovered(_ gesture: UIHoverGestureRecognizer) {
        pencilHovering = gesture.state == .began || gesture.state == .changed
        nativePointerVisible = false
        guard pencilHovering, !isLocalNavigation, canvas.contains(gesture.location(in: self)), canvas.width > 0, canvas.height > 0 else { updateCursor(); return }
        let point = gesture.location(in: self)
        engine?.moveCursor(to: CGPoint(x: (point.x - canvas.minX) / canvas.width * (engine?.remoteWidth ?? 0),
                                      y: (point.y - canvas.minY) / canvas.height * (engine?.remoteHeight ?? 0)))
        updateCursor()
    }

    private func nativeTouches(_ touches: Set<UITouch>, event: UIEvent?, ending: Bool = false, cancelled: Bool = false) -> Set<UITouch> {
        let native = touches.filter { $0.type == .indirectPointer || $0.type == .pencil }
        for touch in native {
            let source: TrackpadEngine.AbsolutePointerSource = touch.type == .pencil ? .pencil : .mouse
            let point = touch.location(in: self)
            nativePointerVisible = source == .mouse
            if isLocalNavigation {
                if !ending && !cancelled, let previous = lastNativeNavigationLocations[source] {
                    onPan?(point.x - previous.x, point.y - previous.y)
                }
                lastNativeNavigationLocations[source] = ending || cancelled ? nil : point
                continue
            }
            if cancelled { engine?.releaseAbsolutePointer(source); continue }
            var buttons: RFBConstants.ButtonMask = []
            if source == .pencil { if !ending { buttons = .left } }
            else if let mask = event?.buttonMask {
                if mask.contains(.primary) { buttons.insert(.left) }
                if mask.contains(.secondary) { buttons.insert(.right) }
                if mask.contains(.button(3)) { buttons.insert(.middle) }
            }
            // A contact outside the desktop cannot begin a remote click, while
            // an existing drag may finish at the nearest desktop edge.
            guard canvas.width > 0, canvas.height > 0 else {
                if ending { engine?.releaseAbsolutePointer(source) }
                continue
            }
            guard canvas.contains(point) || !(engine?.absolutePointerButtons(for: source).isEmpty ?? true) else { continue }
            engine?.handleAbsolutePointer(point: CGPoint(x: point.x - canvas.minX, y: point.y - canvas.minY),
                                          viewSize: canvas.size, buttons: buttons, source: source)
        }
        updateCursor()
        return touches.subtracting(native)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if hardwareKeyboardEnabled { becomeFirstResponder() }
        let remaining = nativeTouches(touches, event: event)
        if !remaining.isEmpty { super.touchesBegan(remaining, with: event) }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let remaining = nativeTouches(touches, event: event)
        if !remaining.isEmpty { super.touchesMoved(remaining, with: event) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let remaining = nativeTouches(touches, event: event, ending: true)
        if !remaining.isEmpty { super.touchesEnded(remaining, with: event) }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        let remaining = nativeTouches(touches, event: event, cancelled: true)
        if !remaining.isEmpty { super.touchesCancelled(remaining, with: event) }
    }

    func releaseAllInput() {
        stopKeyRepeat()
        keyboard.releaseAll()
        releaseDrag()
        engine?.releaseAbsolutePointer(.mouse)
        engine?.releaseAbsolutePointer(.pencil)
        lastNativeNavigationLocations.removeAll()
        scrollAccumulator = NativeScrollAccumulator()
        hardwareScrollAccumulator = NativeScrollAccumulator()
        pencilHovering = false
    }

    @objc private func hardwareScrolled(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began { hardwareScrollAccumulator = NativeScrollAccumulator() }
        let delta = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        guard gesture.state == .began || gesture.state == .changed else { return }
        guard delta.x.isFinite, delta.y.isFinite else { return }
        if isLocalNavigation { onPan?(delta.x, delta.y); return }
        for wheel in hardwareScrollAccumulator.consume(dx: delta.x, dy: delta.y, pointsPerTick: 8) {
            switch wheel {
            case .scrollUp: engine?.handleScroll(deltaY: 8)
            case .scrollDown: engine?.handleScroll(deltaY: -8)
            case .scrollLeft: engine?.handleHorizontalScroll(deltaX: 8)
            default: engine?.handleHorizontalScroll(deltaX: -8)
            }
        }
    }

    private func movePointer(dx: CGFloat, dy: CGFloat) {
        guard let engine, canvas.width > 0 else { return }
        // Finger translation is measured in screen points, not remote pixels.
        engine.handlePanDelta(dx: dx, dy: dy, coordinateScale: engine.remoteWidth / canvas.width)
        guard !isLocalNavigation, engine.mode == .trackpad else { return }
        let delta = RemoteViewportNavigation.followDelta(
            cursor: CGPoint(x: engine.cursorX, y: engine.cursorY),
            remoteSize: CGSize(width: engine.remoteWidth, height: engine.remoteHeight),
            canvas: canvas, viewport: bounds.size)
        if delta != .zero {
            // Apply locally now so subsequent finger samples use the same
            // transform, even before SwiftUI publishes the viewport offset.
            canvas = canvas.offsetBy(dx: delta.width, dy: delta.height)
            onPan?(delta.width, delta.height)
        }
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
        nativePointerVisible = false
        guard gesture.state == .ended else { return }
        if let inputDiagnosticIdentifier {
            InputDiagnostics.enabled?.record(isLocalNavigation ? .tapSuppressed : .tapRecognized,
                                             session: inputDiagnosticIdentifier, flags: diagnosticInputFlags,
                                             buttons: button(for: gesture.numberOfTouchesRequired).rawValue)
        }
        guard !isLocalNavigation else { return }
        positionDirectly(gesture.location(in: self))
        engine?.click(button: button(for: gesture.numberOfTouchesRequired))
        updateCursor()
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        nativePointerVisible = false
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
        guard !isLocalNavigation, !isPinching else { return }
        if gesture.state == .began {
            positionDirectly(gesture.location(in: self))
            dragButton = button(for: gesture.numberOfTouchesRequired)
            lastHoldLocation = gesture.location(in: self)
            engine?.beginDrag(button: dragButton)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else if gesture.state == .changed {
            guard !dragButton.isEmpty else { return }
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
        updateCursor()
    }

    @objc private func scrolled(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began { scrollAccumulator = NativeScrollAccumulator() }
        let delta = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        guard dragButton.isEmpty, !isPinching else { return }
        guard gesture.state == .began || gesture.state == .changed else { return }
        guard delta.x.isFinite, delta.y.isFinite else { return }
        if isLocalNavigation { onPan?(delta.x, delta.y); return }
        for wheel in scrollAccumulator.consume(dx: delta.x, dy: delta.y, pointsPerTick: 8) {
            switch wheel {
            case .scrollUp: engine?.handleScroll(deltaY: 8)
            case .scrollDown: engine?.handleScroll(deltaY: -8)
            case .scrollLeft: engine?.handleHorizontalScroll(deltaX: 8)
            default: engine?.handleHorizontalScroll(deltaX: -8)
            }
        }
    }

    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began { initialZoom = zoom; releaseDrag() }
        if gesture.state == .began || gesture.state == .changed { onZoom?(max(1, min(4, initialZoom * gesture.scale))) }
    }

    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let tap = gesture as? UITapGestureRecognizer, tap.numberOfTouchesRequired == 1,
           let inputDiagnosticIdentifier {
            var flags = diagnosticInputFlags
            if touch.type == .direct { flags.insert(.directTouch) }
            InputDiagnostics.enabled?.record(.tapContact, session: inputDiagnosticIdentifier, flags: flags)
        }
        guard gesture is UIScreenEdgePanGestureRecognizer else { return true }
        guard boundaryGesturesEnabled, !isLocalNavigation,
              UIApplication.shared.applicationState == .active,
              let window, isInFrontmostPresentation else { return false }
        if gesture.numberOfTouches == 0 {
            boundaryTouchOrigins[ObjectIdentifier(gesture)] = touch.location(in: window)
        }
        return true
    }

    private var diagnosticInputFlags: InputDiagnostics.Flags {
        var flags: InputDiagnostics.Flags = []
        if isLocalNavigation { flags.insert(.localNavigation) }
        if engine?.mode == .trackpad { flags.insert(.trackpad) }
        if window != nil && UIApplication.shared.applicationState == .active { flags.insert(.foreground) }
        return flags
    }

    override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        if let edgeGesture = gesture as? UIScreenEdgePanGestureRecognizer {
            recordBoundaryDiagnostics(stage: "should-begin", gesture: edgeGesture)
            guard boundaryGesturesEnabled, !isLocalNavigation, UIApplication.shared.applicationState == .active,
                  let window, isInFrontmostPresentation else { return false }
            let delta = edgeGesture.translation(in: window)
            guard delta.x.isFinite, delta.y.isFinite else { return false }
            // UIKit may reset translation immediately before this delegate
            // callback. Use velocity for direction when translation is zero;
            // final dispatch still requires the actual inward travel distance.
            let direction = delta == .zero ? edgeGesture.velocity(in: window) : delta
            guard direction.x.isFinite, direction.y.isFinite else { return false }
            let largest = max(abs(direction.x), abs(direction.y))
            if largest == 0 { return true }
            let location = edgeGesture.location(in: window)
            // Reject direction before recognition so sideways/outward edge
            // motion can still become an ordinary canvas pan. Final dispatch
            // separately validates actual traveled distance.
            return ScreenBoundaryGesture.target(
                start: boundaryTouchOrigins[ObjectIdentifier(edgeGesture)] ??
                    CGPoint(x: location.x - delta.x, y: location.y - delta.y),
                translation: CGPoint(x: direction.x * 48 / largest, y: direction.y * 48 / largest),
                size: window.bounds.size) != nil
        }
        return !(isLocalNavigation && gesture is UILongPressGestureRecognizer)
    }

    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
        // Only movement needs arbitration with window-level edge pans. A tap
        // cannot also complete an edge swipe; making it wait on all four window
        // recognizers can suppress clicks while ordinary pointer pans still work.
        // Dynamic failure relationships do not retain detached window recognizers.
        boundaryGesturesEnabled && !(gesture is UIScreenEdgePanGestureRecognizer) &&
            gesture is UIPanGestureRecognizer &&
            boundaryGestures.contains { $0 === other }
    }

    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Pinch recognition can continue if a two-finger pan starts first.
        // While it is active, held/scrolled suppress remote button and wheel
        // events; pinched releases any drag that began before the pinch.
        func isTwoFingerPan(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            return pan.minimumNumberOfTouches == 2 && pan.maximumNumberOfTouches == 2
        }
        if gesture === pinchRecognizer && isTwoFingerPan(other) ||
            other === pinchRecognizer && isTwoFingerPan(gesture) { return true }
        // Pinch may take over a hold that started before the fingers separate;
        // pinched releases that button and held suppresses input while pinching.
        if gesture === pinchRecognizer && other is UILongPressGestureRecognizer ||
            other === pinchRecognizer && gesture is UILongPressGestureRecognizer { return true }
        // A pan that already started must cancel a pending long press. A hold
        // that wins first continues its drag through held's changed events.
        return false
    }

    func updateCursor() {
        guard let engine else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let heldButtons = engine.activeButtons
        cursor.isHidden = isLocalNavigation || (nativePointerVisible && heldButtons.isEmpty) || (engine.mode != .trackpad && heldButtons.isEmpty && !pencilHovering)
        cursor.position = CGPoint(x: canvas.minX + engine.cursorX * canvas.width / max(1, engine.remoteWidth),
                                  y: canvas.minY + engine.cursorY * canvas.height / max(1, engine.remoteHeight))
        let color: UIColor = heldButtons.contains(.right) ? .systemRed : heldButtons.contains(.middle) ? .systemGreen : heldButtons.isEmpty ? .white : .systemBlue
        cursor.fillColor = color.cgColor
        accessibilityValue = isFullscreen ? AppLocalization.string("Full Screen") : nil
        #if DEBUG
        if ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_DIAGNOSTICS"] == "1" {
            accessibilityValue = boundaryDiagnosticValue
        }
        #endif
        accessibilityCustomActions = [UIAccessibilityCustomAction(name: AppLocalization.string(isFullscreen ? "Exit Full Screen" : "Enter Full Screen"), target: self, selector: #selector(toggleFullscreenAccessibility))]
        CATransaction.commit()
    }
}
#endif
