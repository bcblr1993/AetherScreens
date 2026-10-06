import SwiftUI

struct DeviceLibraryStorageSection: View {
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    @ObservedObject var controller: DeviceLibrarySyncController

    var body: some View {
        Section {
            Picker(AppLocalization.string("Storage"), selection: Binding(
                get: { controller.storageMode }, set: { controller.selectStorage($0) })) {
                Text(AppLocalization.string("On This Device")).tag(DeviceLibraryStorage.local)
                Text("iCloud").tag(DeviceLibraryStorage.iCloud)
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("library-storage")
            .accessibilityValue(AppLocalization.string(controller.storageMode == .local ? "On This Device" : "iCloud"))

            if controller.storageMode == .iCloud || retry {
                HStack {
                    if controller.status == .synchronizing { ProgressView().controlSize(.small) }
                    Text(AppLocalization.string(controller.status.messageKey))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("library-sync-status")
                }
            }
            if controller.storageMode == .iCloud {
                Button(AppLocalization.string(retry ? "Retry Sync" : "Sync Now")) {
                    Task { await controller.synchronizeNow() }
                }
                .disabled(controller.status == .synchronizing)
                .accessibilityIdentifier("library-sync-now")
            }
        } header: {
            Text(AppLocalization.string("Saved Computers"))
        } footer: {
            Text(AppLocalization.string(controller.storageMode == .local
                ? "Saved computers stay on this device."
                : "Saved computer preferences can sync through iCloud. Passwords and SSH keys remain in this device’s Keychain."))
        }
    }

    private var retry: Bool {
        if case .failed = controller.status { return true }
        return false
    }
}
