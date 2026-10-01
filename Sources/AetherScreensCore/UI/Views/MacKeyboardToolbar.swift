import SwiftUI

/// Mac-tailored keyboard accessory toolbar with Screens-style 3-state sticky modifiers,
/// quick actions, F1-F12 function row, and text transmission.
public struct MacKeyboardToolbar: View {
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    @ObservedObject public var viewModel: SessionViewModel
    @State private var showingTextInput: Bool = false
    @State private var showingFunctionKeys: Bool = false
    @Binding private var showingCustomization: Bool

    public init(viewModel: SessionViewModel, showingCustomization: Binding<Bool>) {
        self.viewModel = viewModel
        _showingCustomization = showingCustomization
    }

    public var body: some View {
        VStack(spacing: 0) {
            Divider()

            // Optional Quick Text Input Bar (Typing directly into Mac)
            if showingTextInput {
                HStack(spacing: 8) {
                    Image(systemName: "keyboard")
                        .foregroundColor(.secondary)

                    TextField(AppLocalization.string("Type or paste text to send to Mac..."), text: $viewModel.textInputBuffer)
                        .textFieldStyle(.plain)
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
                        .buttonStyle(.plain)
                    }

                    Button {
                        withAnimation { showingTextInput = false }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.04))
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
                .background(Color.primary.opacity(0.02))
                Divider()
            }

            // Main Primary Keyboard Bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.keyboardConfiguration.items.filter(\.isVisible)) { item in
                        configuredButton(item.action)
                    }
                    Button {
                        showingCustomization = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .padding(8)
                    }
                    .accessibilityLabel(AppLocalization.string("Customize Keyboard Toolbar"))
                    .help(AppLocalization.string("Customize Keyboard Toolbar"))
                    .buttonStyle(.plain)

                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(.bar)
        }
        .background(.regularMaterial)
        .environment(\.keyboardButtonHeight, buttonHeight)
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
                Label(AppLocalization.string("Actions"), systemImage: "command")
                    .padding(.horizontal, 10).frame(minHeight: buttonHeight)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }
        case .command: ModifierKeyButton(symbol: "⌘", label: "Cmd", state: viewModel.cmdState) { viewModel.cycleCmd() }
        case .option: ModifierKeyButton(symbol: "⌥", label: "Opt", state: viewModel.optState) { viewModel.cycleOption() }
        case .control: ModifierKeyButton(symbol: "⌃", label: "Ctrl", state: viewModel.ctrlState) { viewModel.cycleControl() }
        case .shift: ModifierKeyButton(symbol: "⇧", label: "Shift", state: viewModel.shiftState) { viewModel.cycleShift() }
        case .escape: ActionButton(title: "esc") { viewModel.sendKeyTap(MacKeyMap.escape) }
        case .tab: ActionButton(title: "tab") { viewModel.sendKeyTap(MacKeyMap.tab) }
        case .space: ActionButton(title: "space") { viewModel.sendKeyTap(MacKeyMap.space) }
        case .enter: ActionButton(title: "return") { viewModel.sendKeyTap(MacKeyMap.return) }
        case .delete: ActionButton(title: "del") { viewModel.sendKeyTap(MacKeyMap.delete) }
        case .left: ActionButton(icon: "arrow.left") { viewModel.sendKeyTap(MacKeyMap.arrowLeft) }
        case .up: ActionButton(icon: "arrow.up") { viewModel.sendKeyTap(MacKeyMap.arrowUp) }
        case .down: ActionButton(icon: "arrow.down") { viewModel.sendKeyTap(MacKeyMap.arrowDown) }
        case .right: ActionButton(icon: "arrow.right") { viewModel.sendKeyTap(MacKeyMap.arrowRight) }
        case .functionKeys:
            ActionButton(title: "Fn") { withAnimation { showingFunctionKeys.toggle() } }
        case .text:
            ActionButton(title: "Type") { withAnimation { showingTextInput.toggle() } }
        case .paste:
            ActionButton(title: "Paste Text") { viewModel.syncClipboardToMac() }
                .help(AppLocalization.string("Insert local clipboard text into the focused remote field"))
        case .spacer:
            Color.clear.frame(width: 12, height: buttonHeight).accessibilityHidden(true)
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
private struct ModifierKeyButton: View {
    @Environment(\.keyboardButtonHeight) private var buttonHeight
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    let symbol: String
    let label: String
    let state: SessionViewModel.ModifierState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(symbol)
                    .font(.system(size: 14, weight: .bold))
                Text(AppLocalization.string(label))
                    .font(.system(size: 11, weight: .semibold))

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
        .buttonStyle(.plain)
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

private struct ActionButton: View {
    @Environment(\.keyboardButtonHeight) private var buttonHeight
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    var title: String? = nil
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
        .buttonStyle(.plain)
    }
}

private struct KeyboardButtonHeightKey: EnvironmentKey { static let defaultValue: CGFloat = 44 }
private extension EnvironmentValues {
    var keyboardButtonHeight: CGFloat {
        get { self[KeyboardButtonHeightKey.self] }
        set { self[KeyboardButtonHeightKey.self] = newValue }
    }
}
