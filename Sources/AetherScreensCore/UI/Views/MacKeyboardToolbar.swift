import SwiftUI

/// Mac-tailored keyboard accessory toolbar with Screens-style 3-state sticky modifiers,
/// quick actions, F1-F12 function row, and text transmission.
public struct MacKeyboardToolbar: View {
    @ObservedObject public var viewModel: SessionViewModel
    @State private var showingTextInput: Bool = false
    @State private var showingFunctionKeys: Bool = false
    @State private var textInput: String = ""

    public init(viewModel: SessionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            Divider()

            // Optional Quick Text Input Bar (Typing directly into Mac)
            if showingTextInput {
                HStack(spacing: 8) {
                    Image(systemName: "keyboard")
                        .foregroundColor(.secondary)

                    TextField("Type or paste text to send to Mac...", text: $textInput)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            sendEnteredText()
                        }

                    if !textInput.isEmpty {
                        Button {
                            sendEnteredText()
                        } label: {
                            Text("Send")
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
                    // Actions Menu (Spotlight, App Switcher, Mission Control, etc.)
                    Menu {
                        ForEach(MacKeyMap.MacShortcut.allCases) { shortcut in
                            Button {
                                viewModel.executeShortcut(shortcut)
                            } label: {
                                Label(shortcut.rawValue, systemImage: shortcut.iconName)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "command")
                            Text("Actions")
                                .font(.system(size: 13, weight: .medium))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    // 3-State Sticky Modifiers (Screens style: tap once = next key, double tap = locked 🔒)
                    Group {
                        ModifierKeyButton(
                            symbol: "⌘",
                            label: "Cmd",
                            state: viewModel.cmdState
                        ) {
                            viewModel.cycleCmd()
                        }

                        ModifierKeyButton(
                            symbol: "⌥",
                            label: "Opt",
                            state: viewModel.optState
                        ) {
                            viewModel.cycleOption()
                        }

                        ModifierKeyButton(
                            symbol: "⌃",
                            label: "Ctrl",
                            state: viewModel.ctrlState
                        ) {
                            viewModel.cycleControl()
                        }

                        ModifierKeyButton(
                            symbol: "⇧",
                            label: "Shift",
                            state: viewModel.shiftState
                        ) {
                            viewModel.cycleShift()
                        }
                    }

                    Divider()
                        .frame(height: 24)

                    // Special Single-Tap Mac Keys
                    Group {
                        ActionButton(title: "esc") {
                            viewModel.sendKeyTap(MacKeyMap.escape)
                        }

                        ActionButton(title: "tab") {
                            viewModel.sendKeyTap(MacKeyMap.tab)
                        }

                        ActionButton(title: "space") {
                            viewModel.sendKeyTap(MacKeyMap.space)
                        }

                        ActionButton(title: "return") {
                            viewModel.sendKeyTap(MacKeyMap.return)
                        }

                        ActionButton(title: "del") {
                            viewModel.sendKeyTap(MacKeyMap.delete)
                        }
                    }

                    Divider()
                        .frame(height: 24)

                    // Directional Arrows
                    Group {
                        ActionButton(icon: "arrow.left") {
                            viewModel.sendKeyTap(MacKeyMap.arrowLeft)
                        }
                        ActionButton(icon: "arrow.up") {
                            viewModel.sendKeyTap(MacKeyMap.arrowUp)
                        }
                        ActionButton(icon: "arrow.down") {
                            viewModel.sendKeyTap(MacKeyMap.arrowDown)
                        }
                        ActionButton(icon: "arrow.right") {
                            viewModel.sendKeyTap(MacKeyMap.arrowRight)
                        }
                    }

                    Divider()
                        .frame(height: 24)

                    // F1-F12 Toggle Button
                    Button {
                        withAnimation { showingFunctionKeys.toggle() }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "slider.horizontal.3")
                            Text("Fn")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(showingFunctionKeys ? Color.accentColor : Color.secondary.opacity(0.12))
                        .foregroundColor(showingFunctionKeys ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    // Direct Text Input Drawer Toggle
                    Button {
                        withAnimation { showingTextInput.toggle() }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "character.cursor.ibeam")
                            Text("Type")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(showingTextInput ? Color.accentColor : Color.secondary.opacity(0.12))
                        .foregroundColor(showingTextInput ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    // Clipboard Paste to Mac
                    Button {
                        viewModel.syncClipboardToMac()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.clipboard")
                            Text("Paste Text")
                                .font(.system(size: 12))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .help("Insert local clipboard text into the focused remote field")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(.bar)
        }
        .background(.regularMaterial)
    }

    private func sendEnteredText() {
        guard !textInput.isEmpty else { return }
        viewModel.sendTextString(textInput)
        textInput = ""
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
    let symbol: String
    let label: String
    let state: SessionViewModel.ModifierState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(symbol)
                    .font(.system(size: 14, weight: .bold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))

                if state == .locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
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
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(Color.secondary.opacity(0.12))
            .foregroundColor(.primary)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
