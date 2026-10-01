import SwiftUI

public struct KeyboardToolbarSettingsView: View {
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    @Binding var configuration: KeyboardToolbarConfiguration
    @Environment(\.dismiss) private var dismiss

    public init(configuration: Binding<KeyboardToolbarConfiguration>) { _configuration = configuration }
    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(AppLocalization.string("Button Size"), selection: $configuration.size) {
                        ForEach(KeyboardToolbarConfiguration.Size.allCases, id: \.self) { size in
                            Text(AppLocalization.string(size.rawValue)).tag(size)
                        }
                    }
                    Picker(AppLocalization.string("Keyboard Position"), selection: $configuration.position) {
                        ForEach(KeyboardToolbarConfiguration.Position.allCases, id: \.self) { position in
                            Text(AppLocalization.string(position.rawValue)).tag(position)
                        }
                    }
                }
                Section(AppLocalization.string("Buttons and Spacers")) {
                    ForEach($configuration.items) { $item in
                        HStack(spacing: 8) {
                            Toggle(AppLocalization.string(item.action.rawValue), isOn: $item.isVisible)
                                .accessibilityIdentifier("keyboard-visible-\(item.action.rawValue)")
                            Button {
                                configuration.move(item.id, by: -1)
                            } label: { Image(systemName: "arrow.up") }
                            .accessibilityLabel(AppLocalization.string("Move Up"))
                            .disabled(configuration.items.first?.id == item.id)
                            Button {
                                configuration.move(item.id, by: 1)
                            } label: { Image(systemName: "arrow.down") }
                            .accessibilityLabel(AppLocalization.string("Move Down"))
                            .disabled(configuration.items.last?.id == item.id)
                            if item.action == .spacer {
                                Button {
                                    configuration.items.removeAll { $0.id == item.id }
                                } label: { Image(systemName: "minus.circle") }
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
                    Button(AppLocalization.string("Reset Toolbar")) { configuration = KeyboardToolbarConfiguration() }
                }
            }
            .navigationTitle(AppLocalization.string("Customize Keyboard Toolbar"))
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
