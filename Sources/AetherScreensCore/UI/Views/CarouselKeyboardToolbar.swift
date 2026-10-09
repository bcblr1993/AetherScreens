#if os(iOS)
import SwiftUI
import UIKit

/// Native touch filtering keeps a mouse/trackpad over the ring on the remote canvas.
struct CarouselKeyboardToolbar: View {
    @ObservedObject var viewModel: SessionViewModel
    var disconnect: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var minimized = false
    @State private var offset = CGSize.zero
    @State private var menu: CarouselMenu?

    var body: some View {
        GeometryReader { geometry in
            let diameter: CGFloat = minimized ? 56 : 216
            let center = clampedCenter(size: geometry.size, diameter: diameter, offset: offset)
            CarouselRing(minimized: minimized, reduceMotion: reduceMotion, commandsEnabled: viewModel.canSendRemoteCommands, select: { action in
                if action == "expand" { minimized = false }
                else if action == "minimize" { menu = nil; minimized = true }
                else if action != "actions" && !viewModel.canSendRemoteCommands { return }
                else if action == "paste" { viewModel.syncClipboardToMac() }
                else { menu = CarouselMenu(rawValue: action) }
            }, move: { translation, _ in
                let proposed = CGSize(width: offset.width + translation.width,
                                      height: offset.height + translation.height)
                let position = clampedCenter(size: geometry.size, diameter: diameter, offset: proposed)
                offset = CGSize(width: position.x - geometry.size.width * 0.7,
                                height: position.y - geometry.size.height * 0.65)
            })
            .frame(width: diameter, height: diameter)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(minimized ? "carousel-minimized" : "carousel-expanded")
            .popover(item: $menu) { selection in
                menuContent(selection)
                    .presentationCompactAdaptation(.popover)
            }
            .position(center)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.9), value: minimized)
            .onReceive(viewModel.remoteInteraction) { _ in
                if !minimized { menu = nil; minimized = true }
            }
            .onChange(of: viewModel.canSendRemoteCommands) { enabled in
                if !enabled && menu != .actions { menu = nil }
            }
            .onReceive(viewModel.pencilToolbarToggle) { location in
                menu = nil
                if minimized, let location {
                    let position = clampedCenter(size: geometry.size, diameter: 216,
                                                 offset: CGSize(width: location.x - geometry.size.width * 0.7,
                                                                height: location.y - geometry.size.height * 0.65))
                    offset = CGSize(width: position.x - geometry.size.width * 0.7,
                                    height: position.y - geometry.size.height * 0.65)
                }
                minimized.toggle()
            }
            .onChange(of: geometry.size) { size in
                let position = clampedCenter(size: size, diameter: diameter, offset: offset)
                offset = CGSize(width: position.x - size.width * 0.7,
                                height: position.y - size.height * 0.65)
            }
        }
    }

    private func clampedCenter(size: CGSize, diameter: CGFloat, offset: CGSize) -> CGPoint {
        let horizontalMargin = min(size.width / 2, diameter / 2 + 8)
        let verticalMargin = min(size.height / 2, diameter / 2 + 8)
        return CGPoint(x: max(horizontalMargin, min(size.width - horizontalMargin, size.width * 0.7 + offset.width)),
                       y: max(verticalMargin, min(size.height - verticalMargin, size.height * 0.65 + offset.height)))
    }

    private var editingCommands: [(String, Character)] { [("Cut", "x"), ("Copy", "c"), ("Paste", "v"), ("Select All", "a"), ("Undo", "z")] }

    @ViewBuilder private func menuContent(_ selection: CarouselMenu) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(AppLocalization.string(selection.title)).font(.headline)
                Spacer()
                Button(AppLocalization.string("Done")) { menu = nil }
                    .accessibilityIdentifier("carousel-menu-done")
            }
            ScrollView {
                VStack(spacing: 12) {
                    switch selection {
                    case .modifiers:
                        HStack(spacing: 8) {
                            ModifierKeyButton(symbol: "⌘", label: "Cmd", state: viewModel.cmdState) { viewModel.cycleCmd() }
                                .accessibilityIdentifier("carousel-modifier-command")
                            ModifierKeyButton(symbol: "⇧", label: "Shift", state: viewModel.shiftState) { viewModel.cycleShift() }
                                .accessibilityIdentifier("carousel-modifier-shift")
                        }
                        HStack(spacing: 8) {
                            ModifierKeyButton(symbol: "⌥", label: "Opt", state: viewModel.optState) { viewModel.cycleOption() }
                                .accessibilityIdentifier("carousel-modifier-option")
                            ModifierKeyButton(symbol: "⌃", label: "Ctrl", state: viewModel.ctrlState) { viewModel.cycleControl() }
                                .accessibilityIdentifier("carousel-modifier-control")
                        }
                    case .navigation:
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            key("Left Arrow", MacKeyMap.arrowLeft, icon: "arrow.left")
                            key("Right Arrow", MacKeyMap.arrowRight, icon: "arrow.right")
                            key("Up Arrow", MacKeyMap.arrowUp, icon: "arrow.up")
                            key("Down Arrow", MacKeyMap.arrowDown, icon: "arrow.down")
                            key("Home", MacKeyMap.home); key("End", MacKeyMap.end)
                            key("Page Up", MacKeyMap.pageUp); key("Page Down", MacKeyMap.pageDown)
                            key("tab", MacKeyMap.tab); key("esc", MacKeyMap.escape, repeating: false)
                        }
                    case .functionKeys:
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(0..<12, id: \.self) { index in
                                key("F\(index + 1)", MacKeyMap.f1 + UInt32(index), repeating: false)
                            }
                        }
                    case .edit:
                        ForEach(editingCommands, id: \.0) { title, character in
                            Button(AppLocalization.string(title)) { viewModel.sendCommandShortcut(character) }
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .accessibilityIdentifier("carousel-edit-" + title)
                        }
                    case .shortcuts:
                        ForEach(MacKeyMap.MacShortcut.allCases) { shortcut in
                            Button { viewModel.executeShortcut(shortcut) } label: {
                                Label(AppLocalization.string(shortcut.rawValue), systemImage: shortcut.iconName)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            .accessibilityIdentifier("carousel-shortcut-" + shortcut.id)
                        }
                    case .typing:
                        CarouselTextInput(viewModel: viewModel)
                    case .actions:
                        Button(AppLocalization.string("Fit to Window")) { viewModel.zoomScale = 1; viewModel.viewOffset = .zero }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityIdentifier("carousel-action-fit")
                        Button(AppLocalization.string("Reconnect")) { menu = nil; viewModel.reconnectSession() }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityIdentifier("carousel-action-reconnect")
                        Button(AppLocalization.string("Send to Remote Clipboard")) { viewModel.sendLocalClipboardToRemote() }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .disabled(!viewModel.canSendRemoteCommands)
                        Button(AppLocalization.string("Disconnect"), role: .destructive) { menu = nil; disconnect() }
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }.frame(maxHeight: 320)
                .disabled(selection != .actions && !viewModel.canSendRemoteCommands)
        }
        .padding(16)
        .frame(width: 260)
        .environment(\.toolbarKeyRepeat, viewModel.keyboardConfiguration.keyRepeat)
        .environment(\.toolbarRepeatEnabled, viewModel.isKeyboardVisible && !viewModel.isObserveOnly)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("carousel-menu-" + selection.rawValue)
    }

    private func key(_ title: String, _ symbol: UInt32, icon: String? = nil, repeating: Bool = true) -> some View {
        ActionButton(title: icon == nil ? title : nil, icon: icon, repeatKey: repeating ? symbol : nil, repeatSession: viewModel) {
            viewModel.sendKeyTap(symbol)
        }
        .accessibilityLabel(AppLocalization.string(title))
        .accessibilityIdentifier("carousel-key-" + title)
    }
}

private enum CarouselMenu: String, Identifiable {
    case actions, functionKeys, typing, modifiers, navigation, shortcuts, edit
    var id: String { rawValue }
    var title: String {
        switch self {
        case .actions: return "Actions"
        case .functionKeys: return "Function Keys"
        case .typing: return "Type"
        case .modifiers: return "Modifier Keys"
        case .navigation: return "Navigation Keys"
        case .shortcuts: return "Shortcuts"
        case .edit: return "Edit"
        }
    }
}

private struct CarouselTextInput: View {
    @ObservedObject var viewModel: SessionViewModel
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 12) {
            TextField(AppLocalization.string("Type or paste text to send to Mac..."), text: $viewModel.textInputBuffer)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .accessibilityIdentifier("carousel-text-input")
                .onSubmit(send)
            Button(AppLocalization.string("Send"), action: send)
                .disabled(viewModel.textInputBuffer.isEmpty)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("carousel-text-send")
        }
        .onDisappear { focused = false }
    }
    private func send() {
        viewModel.sendTextString(viewModel.textInputBuffer)
        viewModel.textInputBuffer = ""
        focused = false
    }
}

private struct CarouselRing: UIViewRepresentable {
    let minimized: Bool
    let reduceMotion: Bool
    let commandsEnabled: Bool
    let select: (String) -> Void
    let move: (CGSize, Bool) -> Void
    func makeUIView(context: Context) -> CarouselRingView { CarouselRingView() }
    func updateUIView(_ view: CarouselRingView, context: Context) {
        view.select = select; view.move = move; view.reduceMotion = reduceMotion
        view.minimized = minimized
        view.commandsEnabled = commandsEnabled
        view.refreshLabels()
        view.setNeedsLayout()
    }
}

private final class CarouselTouchButton: UIButton {
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard touch.type == .direct || touch.type == .pencil else { return false }
        return super.beginTracking(touch, with: event)
    }
}

private final class CarouselRingView: UIView {
    var select: ((String) -> Void)?
    var move: ((CGSize, Bool) -> Void)?
    var reduceMotion = false
    var minimized = false
    var commandsEnabled = true
    private let material = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let ringMask = CAShapeLayer()
    private let groups = [("actions", "slider.horizontal.3", "Actions"), ("functionKeys", "f.cursive", "Function Keys"),
                          ("typing", "keyboard", "Type"), ("modifiers", "command", "Modifier Keys"),
                          ("navigation", "arrow.up.and.down.and.arrow.left.and.right", "Navigation Keys"),
                          ("shortcuts", "bolt", "Shortcuts"), ("paste", "doc.on.clipboard", "Paste Text"),
                          ("edit", "scissors", "Edit")]
    private var buttons: [CarouselTouchButton] = []
    private let expand = CarouselTouchButton(type: .system)
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        material.isUserInteractionEnabled = false
        material.layer.mask = ringMask
        ringMask.fillRule = .evenOdd
        addSubview(material)
        for (index, group) in groups.enumerated() {
            let button = CarouselTouchButton(type: .system)
            button.tag = index
            button.setImage(UIImage(systemName: group.1), for: .normal)
            button.addTarget(self, action: #selector(selected(_:)), for: .touchUpInside)
            button.addTarget(self, action: #selector(pressed(_:)), for: .touchDown)
            button.addTarget(self, action: #selector(released(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
            button.accessibilityIdentifier = "carousel-group-" + group.0
            addSubview(button); buttons.append(button)
        }
        expand.setImage(UIImage(systemName: "circle.grid.3x3.fill"), for: .normal)
        expand.accessibilityIdentifier = "carousel-expand"
        expand.addTarget(self, action: #selector(expanded), for: .touchUpInside)
        addSubview(expand)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(dragged(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue), NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        addGestureRecognizer(pan)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.2; layer.shadowRadius = 12; layer.shadowOffset = CGSize(width: 0, height: 4)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    func refreshLabels() {
        for (index, group) in groups.enumerated() {
            buttons[index].accessibilityLabel = AppLocalization.string(group.2)
            buttons[index].isEnabled = group.0 == "actions" || commandsEnabled
        }
        expand.accessibilityLabel = AppLocalization.string("Expand Keyboard Toolbar")
        buttons.first?.accessibilityCustomActions = [UIAccessibilityCustomAction(name: AppLocalization.string("Collapse Keyboard Toolbar"), target: self, selector: #selector(collapse))]
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        material.frame = bounds
        let path = UIBezierPath(ovalIn: bounds)
        if !minimized { path.append(UIBezierPath(ovalIn: bounds.insetBy(dx: bounds.width / 2 - 30, dy: bounds.height / 2 - 30))) }
        ringMask.frame = bounds; ringMask.path = path.cgPath
        expand.isHidden = !minimized
        expand.frame = CGRect(x: (bounds.width - 44) / 2, y: (bounds.height - 44) / 2, width: 44, height: 44)
        for (index, button) in buttons.enumerated() {
            button.isHidden = minimized
            let angle = CGFloat(index) * .pi / 4 - .pi / 2
            button.frame = CGRect(x: bounds.midX + cos(angle) * 80 - 22, y: bounds.midY + sin(angle) * 80 - 22, width: 44, height: 44)
        }
        accessibilityIdentifier = minimized ? "carousel-minimized" : "carousel-expanded"
    }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if event?.allTouches?.contains(where: { $0.type == .indirectPointer }) == true { return false }
        let radius = hypot(point.x - bounds.midX, point.y - bounds.midY)
        return radius <= bounds.width / 2 && (minimized || radius >= 30)
    }
    @objc private func selected(_ sender: UIButton) { select?(groups[sender.tag].0) }
    @objc private func expanded() { select?("expand") }
    @objc private func collapse() -> Bool { select?("minimize"); return true }
    @objc private func pressed(_ sender: UIButton) {
        UIView.animate(withDuration: reduceMotion ? 0 : 0.12) {
            sender.alpha = 0.65
            if !self.reduceMotion { sender.transform = CGAffineTransform(scaleX: 0.94, y: 0.94) }
        }
    }
    @objc private func released(_ sender: UIButton) {
        UIView.animate(withDuration: reduceMotion ? 0 : 0.12) { sender.alpha = 1; sender.transform = .identity }
    }
    @objc private func dragged(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: superview)
        // Consume each delta so overshooting an edge does not delay reversal.
        gesture.setTranslation(.zero, in: superview)
        move?(CGSize(width: translation.x, height: translation.y), [.ended, .cancelled, .failed].contains(gesture.state))
    }
}
#endif
