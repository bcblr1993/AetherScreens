import SwiftUI

struct DisplayQualitySettingsView: View {
    @ObservedObject var viewModel: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(AppLocalization.string("Automatic Compression"), isOn: Binding(
                        get: { viewModel.automaticDisplayQuality && !viewModel.client.isNativeDisplaySession },
                        set: { viewModel.selectAutomaticDisplayQuality($0) }))
                        .accessibilityIdentifier("automatic-display-quality")
                        .disabled(!viewModel.isForegroundSession || viewModel.client.isNativeDisplaySession)
                } footer: {
                    Text(AppLocalization.string("Adjusts compression for active transfers without reconnecting. Servers may ignore quality hints. Native Apple sessions use their own display configuration."))
                }
                Section {
                    Picker(AppLocalization.string("Colors"), selection: Binding(
                        get: { viewModel.displayColorDepth },
                        set: { viewModel.selectDisplayColorDepth($0) })) {
                        Text(AppLocalization.string("Full Color")).tag(RFBColorDepth.fullColor)
                        Text(AppLocalization.string("Reduced Colors")).tag(RFBColorDepth.rgb565)
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("display-color-depth")
                    .disabled(!viewModel.isForegroundSession)
                } footer: {
                    Text(AppLocalization.string("Reduced colors use less data but may show color banding. Changing this setting reconnects. Desktop size stays the same."))
                }
            }
            .navigationTitle(AppLocalization.string("Display Quality"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("Done")) { dismiss() }
                }
            }
        }
    }
}
