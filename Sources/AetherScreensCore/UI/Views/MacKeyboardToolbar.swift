import SwiftUI

/// Mac-tailored keyboard accessory toolbar with Screens-style 3-state sticky modifiers,
/// quick actions, F1-F12 function row, and text transmission.
public struct MacKeyboardToolbar: View {
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    @ObservedObject public var viewModel: SessionViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingTextInput: Bool = false
    @State private var showingFunctionKeys: Bool = false
    @FocusState private var textInputFocused: Bool
    private let isCollapsed: Bool
    private let usesSideDock: Bool
    @Binding private var showingCustomization: Bool

    public init(viewModel: SessionViewModel, showingCustomization: Binding<Bool>, usesSideDock: Bool = false, isCollapsed: Bool = false) {
        self.viewModel = viewModel
        self.usesSideDock = usesSideDock
        self.isCollapsed = isCollapsed
        _showingCustomization = showingCustomization
    }

    public var body: some View {
        VStack(spacing: 0) {
            Divider()

            // Optional Quick Text Input Bar (Typing directly into Mac)
            // Draft and expansion state live above the native editor. Recreate the editor
            // after collapse so UIKit cannot restore a hidden first responder.
            if showingTextInput && !isCollapsed {
                HStack(spacing: 8) {
                    Image(systemName: "keyboard")
                        .foregroundColor(.secondary)

                    TextField(AppLocalization.string("Type or paste text to send to Mac..."), text: $viewModel.textInputBuffer)
                        .textFieldStyle(.plain)
                        .focused($textInputFocused)
                        .accessibilityIdentifier("keyboard-text-input")
                        .onSubmit {
                            sendEnteredText()
                        }

                    if !viewModel.textInputBuffer.isEmpty {
                        Button {
                            sendEnteredText()
                        } label: {
                            Text(AppLocalization.string("Send"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.accentColor, in: Capsule())
                        }
                        .buttonStyle(ControlPressStyle())
                    }

                    Button {
                        textInputFocused = false
                        showingTextInput = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(ControlPressStyle())
                    .accessibilityLabel(AppLocalization.string("Close Text Input"))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial)
                .transition(expansionTransition)
                Divider()
            }

            // Optional F1 - F12 Function Key Row
            if showingFunctionKeys {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(1...12, id: \.self) { num in
                            ActionButton(title: "F\(num)") {
                                let keySym = fKeySym(for: num)
                                viewModel.sendKeyTap(keySym)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .background(.regularMaterial)
                .accessibilityIdentifier("keyboard-function-row")
                .transition(expansionTransition)
                Divider()
            }

            // The phone landscape dock scrolls vertically without resizing the canvas.
            ScrollView(usesSideDock ? .vertical : .horizontal, showsIndicators: false) {
                let layout = usesSideDock ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    ForEach(viewModel.keyboardConfiguration.items.filter(\.isVisible)) { item in
                        configuredButton(item.action)
                            .accessibilityIdentifier("keyboard-action-\(item.action.rawValue)")
                            .accessibilityLabel(AppLocalization.string(item.action.rawValue))
                    }
                    Button {
                        showingCustomization = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .padding(8)
                    }
                    .accessibilityLabel(AppLocalization.string("Customize Keyboard Toolbar"))
                    .help(AppLocalization.string("Customize Keyboard Toolbar"))
                    .buttonStyle(ControlPressStyle())

                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(width: usesSideDock ? 104 : nil, height: usesSideDock ? nil : buttonHeight + 16)
            .background(.bar)
            .accessibilityIdentifier("keyboard-toolbar-scroll")
            .frame(maxWidth: usesSideDock ? .infinity : nil, alignment: .leading)
        }
        .background {
            if !usesSideDock { Rectangle().fill(.regularMaterial) }
        }
        .environment(\.keyboardButtonHeight, buttonHeight)
        .environment(\.toolbarKeyRepeat, viewModel.keyboardConfiguration.keyRepeat)
        .environment(\.toolbarRepeatEnabled, !isCollapsed && viewModel.isKeyboardVisible && !viewModel.isObserveOnly && viewModel.sessionState == .connected)
        .onChange(of: isCollapsed) { value in if value { textInputFocused = false } }
        .onChange(of: showingTextInput) { value in if !value { textInputFocused = false } }
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.9), value: showingTextInput)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.9), value: showingFunctionKeys)
    }

    private var expansionTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: viewModel.keyboardConfiguration.position == .top ? .top : .bottom).combined(with: .opacity)
    }

    private var buttonHeight: CGFloat {
        switch viewModel.keyboardConfiguration.size {
        case .small: return 36
        case .medium: return 44
        case .large: return 52
        }
    }

    @ViewBuilder private func configuredButton(_ action: KeyboardToolbarConfiguration.Action) -> some View {
        switch action {
        case .actions:
            Menu {
                ForEach(MacKeyMap.MacShortcut.allCases) { shortcut in
                    Button { viewModel.executeShortcut(shortcut) } label: {
                        Label(AppLocalization.string(shortcut.rawValue), systemImage: shortcut.iconName)
                    }
                }
            } label: {
                Group {
                    if usesSideDock { Image(systemName: "command") }
                    else { Label(AppLocalization.string("Actions"), systemImage: "command") }
                }
                    .padding(.horizontal, 10).frame(minHeight: buttonHeight)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityLabel(AppLocalization.string("Actions"))
        case .command: ModifierKeyButton(symbol: "⌘", label: "Cmd", state: viewModel.cmdState, compact: usesSideDock) { viewModel.cycleCmd() }
        case .option: ModifierKeyButton(symbol: "⌥", label: "Opt", state: viewModel.optState, compact: usesSideDock) { viewModel.cycleOption() }
        case .control: ModifierKeyButton(symbol: "⌃", label: "Ctrl", state: viewModel.ctrlState) { viewModel.cycleControl() }
        case .shift: ModifierKeyButton(symbol: "⇧", label: "Shift", state: viewModel.shiftState, compact: usesSideDock) { viewModel.cycleShift() }
        case .escape: ActionButton(title: "esc") { viewModel.sendKeyTap(MacKeyMap.escape) }
        case .tab: ActionButton(title: usesSideDock ? nil : "tab", icon: usesSideDock ? "arrow.right.to.line" : nil, repeatKey: MacKeyMap.tab, repeatSession: viewModel) { viewModel.sendKeyTap(MacKeyMap.tab) }
        case .space: ActionButton(title: "space", repeatKey: MacKeyMap.space, repeatSession: viewModel) { viewModel.sendKeyTap(MacKeyMap.space) }
        case .enter: ActionButton(title: usesSideDock ? nil : "return", icon: usesSideDock ? "return" : nil) { viewModel.sendKeyTap(MacKeyMap.return) }
        case .delete: ActionButton(title: usesSideDock ? nil : "del", icon: usesSideDock ? "delete.left" : nil, repeatKey: MacKeyMap.delete, repeatSession: viewModel) { viewModel.sendKeyTap(MacKeyMap.delete) }
        case .left: ActionButton(icon: "arrow.left", repeatKey: MacKeyMap.arrowLeft, repeatSession: viewModel) { viewModel.sendKeyTap(MacKeyMap.arrowLeft) }
        case .up: ActionButton(icon: "arrow.up", repeatKey: MacKeyMap.arrowUp, repeatSession: viewModel) { viewModel.sendKeyTap(MacKeyMap.arrowUp) }
        case .down: ActionButton(icon: "arrow.down", repeatKey: MacKeyMap.arrowDown, repeatSession: viewModel) { viewModel.sendKeyTap(MacKeyMap.arrowDown) }
        case .right: ActionButton(icon: "arrow.right", repeatKey: MacKeyMap.arrowRight, repeatSession: viewModel) { viewModel.sendKeyTap(MacKeyMap.arrowRight) }
        case .home:
            ActionButton(title: "Home", repeatKey: MacKeyMap.home, repeatSession: viewModel) { viewModel.sendKeyTap(MacKeyMap.home) }
        case .end:
            ActionButton(title: "End", repeatKey: MacKeyMap.end, repeatSession: viewModel) { viewModel.sendKeyTap(MacKeyMap.end) }
        case .pageUp:
            ActionButton(title: "PgUp", repeatKey: MacKeyMap.pageUp, repeatSession: viewModel) { viewModel.sendKeyTap(MacKeyMap.pageUp) }
                .accessibilityLabel(AppLocalization.string("Page Up"))
        case .pageDown:
            ActionButton(title: "PgDn", repeatKey: MacKeyMap.pageDown, repeatSession: viewModel) { viewModel.sendKeyTap(MacKeyMap.pageDown) }
                .accessibilityLabel(AppLocalization.string("Page Down"))
        case .functionKeys:
            ActionButton(title: "Fn") { showingFunctionKeys.toggle() }
        case .text:
            ActionButton(title: "Type") { showingTextInput.toggle() }
        case .paste:
            ActionButton(title: usesSideDock ? nil : "Paste Text", icon: usesSideDock ? "doc.on.clipboard" : nil) { viewModel.syncClipboardToMac() }
                .help(AppLocalization.string("Insert local clipboard text into the focused remote field"))
                .contextMenu {
                    Button(AppLocalization.string("Send to Remote Clipboard")) {
                        viewModel.sendLocalClipboardToRemote()
                    }
                    .disabled(viewModel.isObserveOnly || viewModel.sessionState != .connected)
                }
        case .spacer:
            Color.clear.frame(width: usesSideDock ? buttonHeight : 12, height: usesSideDock ? 12 : buttonHeight).accessibilityHidden(true)
        }
    }

    private func sendEnteredText() {
        guard !viewModel.textInputBuffer.isEmpty else { return }
        viewModel.sendTextString(viewModel.textInputBuffer)
        viewModel.textInputBuffer = ""
    }

    private func fKeySym(for num: Int) -> UInt32 {
        switch num {
        case 1: return MacKeyMap.f1
        case 2: return MacKeyMap.f2
        case 3: return MacKeyMap.f3
        case 4: return MacKeyMap.f4
        case 5: return MacKeyMap.f5
        case 6: return MacKeyMap.f6
        case 7: return MacKeyMap.f7
        case 8: return MacKeyMap.f8
        case 9: return MacKeyMap.f9
        case 10: return MacKeyMap.f10
        case 11: return MacKeyMap.f11
        case 12: return MacKeyMap.f12
        default: return MacKeyMap.f1
        }
    }
}

/// Screens-style 3-state modifier key button: Inactive, Active Once, Locked 🔒
struct ModifierKeyButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.keyboardButtonHeight) private var buttonHeight
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    let symbol: String
    let label: String
    let state: SessionViewModel.ModifierState
    var compact: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(symbol)
                    .font(.system(size: 14, weight: .bold))
                if !compact {
                    Text(AppLocalization.string(label))
                        .font(.system(size: 11, weight: .semibold))
                }

                if state == .locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                }
            }
            .padding(.horizontal, 9)
            .frame(minWidth: buttonHeight, minHeight: buttonHeight)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(state == .activeOnce ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(ControlPressStyle())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: state)
        .accessibilityValue(AppLocalization.string(accessibilityState))
    }

    private var accessibilityState: String {
        switch state {
        case .inactive: return "Modifier Inactive"
        case .activeOnce: return "Modifier Once"
        case .locked: return "Modifier Locked"
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .inactive:
            return Color.secondary.opacity(0.12)
        case .activeOnce:
            return Color.accentColor.opacity(0.2)
        case .locked:
            return Color.accentColor
        }
    }

    private var foregroundColor: Color {
        switch state {
        case .inactive:
            return .primary
        case .activeOnce:
            return .accentColor
        case .locked:
            return .white
        }
    }
}

struct ActionButton: View {
    @Environment(\.keyboardButtonHeight) private var buttonHeight
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    var title: String? = nil
    var icon: String? = nil
    var repeatKey: UInt32? = nil
    var repeatSession: SessionViewModel? = nil
    @StateObject private var press = KeyRepeatPress()
    @Environment(\.toolbarRepeatEnabled) private var repeatEnabled
    @Environment(\.toolbarKeyRepeat) private var repeatMode
    let action: () -> Void

    var body: some View {
        Button { press.activate(action) } label: {
            Group {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                } else if let title = title {
                    Text(AppLocalization.string(title))
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .padding(.horizontal, 9)
            .frame(minWidth: buttonHeight, minHeight: buttonHeight)
            .background(Color.secondary.opacity(0.12))
            .foregroundColor(.primary)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(KeyRepeatPressStyle(press: press,
            repeatAction: { if let key = repeatKey { repeatSession?.repeatToolbarKey(key) } },
            endAction: { if let key = repeatKey { repeatSession?.releaseToolbarKey(key) } },
            enabled: repeatEnabled && repeatKey != nil && repeatMode != .off, mode: repeatMode))
        .onChange(of: repeatSession?.inputGeneration) { _ in press.stop() }
    }
}

private struct ToolbarKeyRepeatKey: EnvironmentKey { static let defaultValue = KeyboardToolbarConfiguration.KeyRepeat.normal }
private struct ToolbarRepeatEnabledKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var toolbarKeyRepeat: KeyboardToolbarConfiguration.KeyRepeat {
        get { self[ToolbarKeyRepeatKey.self] }
        set { self[ToolbarKeyRepeatKey.self] = newValue }
    }
    var toolbarRepeatEnabled: Bool {
        get { self[ToolbarRepeatEnabledKey.self] }
        set { self[ToolbarRepeatEnabledKey.self] = newValue }
    }
}

private struct KeyboardButtonHeightKey: EnvironmentKey { static let defaultValue: CGFloat = 44 }
extension EnvironmentValues {
    var keyboardButtonHeight: CGFloat {
        get { self[KeyboardButtonHeightKey.self] }
        set { self[KeyboardButtonHeightKey.self] = newValue }
    }
}
