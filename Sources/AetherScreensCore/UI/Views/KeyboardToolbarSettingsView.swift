import SwiftUI

public struct KeyboardToolbarSettingsView: View {
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    @Binding var configuration: KeyboardToolbarConfiguration
    @Environment(\.dismiss) private var dismiss

    public init(configuration: Binding<KeyboardToolbarConfiguration>) { _configuration = configuration }
    private func updateHardware(_ update: (inout HardwareKeyboardConfiguration) -> Void) {
        var value = configuration.hardwareKeyboard ?? HardwareKeyboardConfiguration()
        update(&value)
        configuration.hardwareKeyboard = value
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(AppLocalization.string("Button Size"), selection: $configuration.size) {
                        ForEach(KeyboardToolbarConfiguration.Size.allCases, id: \.self) { size in
                            Text(AppLocalization.string(size.rawValue)).tag(size)
                        }
                    }
                    .accessibilityIdentifier("keyboard-size")
                    Picker(AppLocalization.string("Keyboard Position"), selection: $configuration.position) {
                        ForEach(KeyboardToolbarConfiguration.Position.allCases, id: \.self) { position in
                            Text(AppLocalization.string(position.rawValue)).tag(position)
                        }
                    }
                    .accessibilityIdentifier("keyboard-position")
                }
                Section(AppLocalization.string("Hardware Keyboard")) {
                    Toggle(AppLocalization.string("Swap Command and Control"), isOn: Binding(
                        get: { configuration.hardwareKeyboard?.swapCommandControl ?? false },
                        set: { value in updateHardware { $0.swapCommandControl = value ? true : nil } }
                    )).accessibilityIdentifier("hardware-swap-command-control")
                    Toggle(AppLocalization.string("Switch Apps with Command-Backslash"), isOn: Binding(
                        get: { configuration.hardwareKeyboard?.commandBackslashSwitchesApps ?? false },
                        set: { value in updateHardware { $0.commandBackslashSwitchesApps = value ? true : nil } }
                    )).accessibilityIdentifier("hardware-command-backslash")
                    #if canImport(UIKit)
                    Toggle(AppLocalization.string("Key Repeat"), isOn: Binding(
                        get: { configuration.hardwareKeyboard?.repeatEnabled ?? true },
                        set: { value in updateHardware { $0.repeatEnabled = value } }
                    )).accessibilityIdentifier("hardware-key-repeat")
                    if configuration.hardwareKeyboard?.repeatEnabled ?? true {
                        Picker(AppLocalization.string("Repeat Delay"), selection: Binding(
                            get: { (configuration.hardwareKeyboard ?? HardwareKeyboardConfiguration()).validatedDelay },
                            set: { value in updateHardware { $0.repeatDelay = value } }
                        )) {
                            ForEach([0.2, 0.5, 1.0, 2.0], id: \.self) { value in
                                Text(AppLocalization.format("%.2f seconds", value)).tag(value)
                            }
                        }.accessibilityIdentifier("hardware-repeat-delay")
                        Picker(AppLocalization.string("Repeat Interval"), selection: Binding(
                            get: { (configuration.hardwareKeyboard ?? HardwareKeyboardConfiguration()).validatedInterval },
                            set: { value in updateHardware { $0.repeatInterval = value } }
                        )) {
                            ForEach([0.03, 0.05, 0.1, 0.2, 0.5], id: \.self) { value in
                                Text(AppLocalization.format("%.2f seconds", value)).tag(value)
                            }
                        }.accessibilityIdentifier("hardware-repeat-interval")
                    }
                    #endif
                }
                #if canImport(UIKit)
                if UIDevice.current.userInterfaceIdiom == .pad {
                    Section {
                        Picker(AppLocalization.string("Pencil Double Tap"), selection: Binding<PencilGestureAction>(
                            get: { configuration.pencilDoubleTapAction ?? .none },
                            set: { configuration.pencilDoubleTapAction = $0 == .none ? nil : $0 }
                        )) {
                            ForEach(PencilGestureAction.allCases) { action in
                                Text(AppLocalization.string(action.rawValue)).tag(action)
                            }
                        }.accessibilityIdentifier("pencil-double-tap-action")
                        if #available(iOS 17.5, *) {
                            Picker(AppLocalization.string("Pencil Squeeze"), selection: Binding<PencilGestureAction>(
                                get: { configuration.pencilSqueezeAction ?? .none },
                                set: { configuration.pencilSqueezeAction = $0 == .none ? nil : $0 }
                            )) {
                                ForEach(PencilGestureAction.allCases) { action in
                                    Text(AppLocalization.string(action.rawValue)).tag(action)
                                }
                            }.accessibilityIdentifier("pencil-squeeze-action")
                        }
                    } header: {
                        Text("Apple Pencil")
                    } footer: {
                        Text(AppLocalization.string("Requires a compatible Apple Pencil with gestures enabled in system settings. Click actions are unavailable in Observe and Pan modes."))
                    }
                }
                #endif
                Section(AppLocalization.string("Buttons and Spacers")) {
                    ForEach($configuration.items) { $item in
                        HStack(spacing: 8) {
                            Toggle(AppLocalization.string(item.action.rawValue), isOn: $item.isVisible)
                                .accessibilityIdentifier("keyboard-visible-\(item.action.rawValue)")
                            Button {
                                configuration.move(item.id, by: -1)
                            } label: {
                                Image(systemName: "arrow.up")
                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .accessibilityLabel(AppLocalization.string("Move Up"))
                            .disabled(configuration.items.first?.id == item.id)
                            Button {
                                configuration.move(item.id, by: 1)
                            } label: {
                                Image(systemName: "arrow.down")
                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .accessibilityLabel(AppLocalization.string("Move Down"))
                            .disabled(configuration.items.last?.id == item.id)
                            if item.action == .spacer {
                                Button {
                                    configuration.items.removeAll { $0.id == item.id }
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .frame(width: 44, height: 44).contentShape(Rectangle())
                                }
                                .accessibilityLabel(AppLocalization.string("Remove Spacer"))
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    .onMove { configuration.items.move(fromOffsets: $0, toOffset: $1) }
                    Button(AppLocalization.string("Add Spacer")) {
                        configuration.items.append(.init(action: .spacer))
                    }
                }
                Section {
                    Button(AppLocalization.string("Reset Toolbar")) { configuration.resetToolbar() }
                }
            }
            .navigationTitle(AppLocalization.string("Keyboard Toolbar"))
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("Done")) { dismiss() }
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            .frame(width: 500, height: 600)
            #endif
        }
        .environment(\.locale, languageSettings.locale)
    }
}
