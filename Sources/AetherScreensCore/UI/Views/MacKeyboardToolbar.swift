import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Mac-tailored keyboard accessory toolbar with Screens-style 3-state sticky modifiers,
/// quick actions, F1-F12 function row, and text transmission.
public struct MacKeyboardToolbar: View {
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    @ObservedObject public var viewModel: SessionViewModel
    @State private var showingTextInput: Bool = false
    @FocusState private var textInputFocused: Bool
    #if canImport(UIKit)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif
    @State private var showingFunctionKeys: Bool = false
    @State private var showingDictation = false
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
                        .focused($textInputFocused)
                        .accessibilityIdentifier("remote-text-input")
                        #if canImport(UIKit)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                        .onAppear { textInputFocused = true }
                        .onSubmit {
                            viewModel.submitTextInput(pressReturn: true)
                        }

                    if !viewModel.textInputBuffer.isEmpty {
                        Button {
                            viewModel.submitTextInput(pressReturn: false)
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
                    .accessibilityLabel(AppLocalization.string("Close"))
                    .accessibilityIdentifier("remote-text-close")
                    .frame(minWidth: 44, minHeight: 44)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.04))
                Divider()
            }

            // Optional F1 - F12 Function Key Row
            if showingFunctionKeys && !usesCompactTextInput {
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
            if !usesCompactTextInput {
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
            .accessibilityIdentifier("keyboard-toolbar-scroll")
            }
        }
        .background(.regularMaterial)
        .environment(\.keyboardButtonHeight, buttonHeight)
        .onDisappear {
            viewModel.cancelToolbarKeyHold()
            viewModel.isTextInputBarVisible = false
        }
        .onChange(of: showingTextInput) { _, visible in
            viewModel.isTextInputBarVisible = visible
            textInputFocused = visible
            if visible { viewModel.cancelToolbarKeyHold() }
        }
        .onChange(of: showingCustomization) { _, visible in
            if visible { viewModel.cancelToolbarKeyHold() }
        }
        .onChange(of: showingDictation) { _, visible in
            if visible { viewModel.cancelToolbarKeyHold() }
        }
        #if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            viewModel.cancelToolbarKeyHold()
        }
        #endif
        .sheet(isPresented: $showingDictation) { RemoteDictationSheet(viewModel: viewModel) }
    }

    private var buttonHeight: CGFloat {
        switch viewModel.keyboardConfiguration.size {
        case .small: return 36
        case .medium: return 44
        case .large: return 52
        }
    }

    private var usesCompactTextInput: Bool {
        #if canImport(UIKit)
        showingTextInput && verticalSizeClass == .compact
        #else
        false
        #endif
    }

    @ViewBuilder private var userPasswordMenu: some View {
        Button { viewModel.typeUserPassword() } label: {
            Label(AppLocalization.string("Type User Password"), systemImage: "key.fill")
        }.disabled(!viewModel.canTypeUserPassword).accessibilityIdentifier("menu-type-user-password")
        Button { viewModel.typeUserPassword(pressReturn: false) } label: {
            Text(AppLocalization.string("Type Password Without Return"))
        }.disabled(!viewModel.canTypeUserPassword).accessibilityIdentifier("menu-type-password-without-return")
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
                Divider()
                userPasswordMenu
                ClipboardMenu(viewModel: viewModel)
                HotCornerMenu(viewModel: viewModel)
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
        case .tab: repeatKey(title: "tab", key: MacKeyMap.tab)
        case .space: ActionButton(title: "space") { viewModel.sendKeyTap(MacKeyMap.space) }
        case .enter: repeatKey(title: "return", key: MacKeyMap.return)
        case .delete: repeatKey(title: "del", key: MacKeyMap.delete)
        case .left: repeatKey(icon: "arrow.left", key: MacKeyMap.arrowLeft)
        case .up: repeatKey(icon: "arrow.up", key: MacKeyMap.arrowUp)
        case .down: repeatKey(icon: "arrow.down", key: MacKeyMap.arrowDown)
        case .right: repeatKey(icon: "arrow.right", key: MacKeyMap.arrowRight)
        case .pageUp, .pageDown:
            if let key = action.keySym { repeatKey(title: action.rawValue, key: key) }
        case .home, .end, .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12:
            if let key = action.keySym { ActionButton(title: action.rawValue) { viewModel.sendKeyTap(key) } }
        case .functionKeys:
            ActionButton(title: "Fn") { withAnimation { showingFunctionKeys.toggle() } }
        case .text:
            ActionButton(title: "Type") { withAnimation { showingTextInput.toggle() } }
        case .paste:
            ActionButton(title: "Paste Text") { viewModel.syncClipboardToMac() }
                .help(AppLocalization.string("Insert local clipboard text into the focused remote field"))
        case .userPassword:
            TypeUserPasswordButton(viewModel: viewModel, height: buttonHeight)
        case .dictation:
            ActionButton(title: "Dictation") { showingDictation = true }
                .disabled(!viewModel.canSendDictation)
                .accessibilityIdentifier("session-dictation")
        case .spacer:
            Color.clear.frame(width: 12, height: buttonHeight).accessibilityHidden(true)
        }
    }

    @ViewBuilder private func repeatKey(title: String? = nil, icon: String? = nil, key: UInt32) -> some View {
        #if canImport(UIKit)
        IOSRepeatKeyButton(title: title, icon: icon, height: buttonHeight, enabled: viewModel.canSendDictation,
                           onBegin: { viewModel.beginToolbarKeyHold(key) },
                           onEnd: { viewModel.endToolbarKeyHold(key, activate: $0) },
                           onActivate: { if viewModel.canSendDictation { viewModel.sendKeyTap(key) } })
            .frame(width: repeatKeyWidth(title), height: buttonHeight)
        #else
        ActionButton(title: title, icon: icon) { viewModel.sendKeyTap(key) }
        #endif
    }

    private func repeatKeyWidth(_ title: String?) -> CGFloat {
        guard let title else { return buttonHeight }
        #if canImport(UIKit)
        let textWidth = (AppLocalization.string(title) as NSString).size(
            withAttributes: [.font: UIFont.systemFont(ofSize: 12, weight: .semibold)]).width + 18
        return max(buttonHeight, ceil(textWidth))
        #else
        return buttonHeight
        #endif
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
