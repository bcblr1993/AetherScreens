import SwiftUI

/// Sheet for adding a new remote computer manually.
public struct AddDeviceSheet: View {
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    @ObservedObject public var viewModel: DeviceListViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var host: String = ""
    @FocusState private var hostFocused: Bool
    @State private var portString: String = "5900"
    @State private var deviceType: RemoteDevice.DeviceType = .mac
    @State private var password: String = ""
    @State private var username: String = ""
    @State private var macAddress: String = ""
    @State private var saveComputer = false
    @State private var sshDraft = SSHConnectionDraft()
    @State private var saveError: String?
    private let onQuickConnect: ((ConnectionRequest, Bool) throws -> Void)?

    public init(viewModel: DeviceListViewModel) {
        self.viewModel = viewModel
        self.onQuickConnect = nil
    }

    public init(viewModel: DeviceListViewModel, onQuickConnect: @escaping (ConnectionRequest, Bool) throws -> Void) {
        self.viewModel = viewModel
        self.onQuickConnect = onQuickConnect
    }

    private var isQuickConnect: Bool { onQuickConnect != nil }
    private var includesSavedDetails: Bool { !isQuickConnect || saveComputer }
    private var request: ConnectionRequest? {
        guard sshDraft.isValid else { return nil }
        return ConnectionRequest(host: host, port: portString, name: includesSavedDetails ? name : "",
                          username: username, password: password, type: deviceType,
                          macAddress: includesSavedDetails ? macAddress : "",
                          ssh: sshDraft.settings, sshPassword: sshDraft.passwordToSave ?? "", sshPrivateKey: sshDraft.privateKeyToSave)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(AppLocalization.string("Device Information"))) {
                    if includesSavedDetails {
                        TextField(AppLocalization.string("Name (e.g. Studio Mac)"), text: $name)
                    }
                    TextField(AppLocalization.string("Tailscale IP / Host (e.g. 100.80.1.25)"), text: $host)
                        .focused($hostFocused)
                        .submitLabel(.done)
                        .onSubmit { hostFocused = false }
                        .autocorrectionDisabled()
                        #if canImport(UIKit)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                    LabeledContent(AppLocalization.string("Port")) {
                        PortTextField(text: $portString)
                            .frame(minWidth: 80)
                            #if canImport(UIKit)
                            .frame(minHeight: 44)
                            #endif
                    }
                }

                if includesSavedDetails {
                    Section(header: Text(AppLocalization.string("Operating System"))) {
                        Picker(AppLocalization.string("Device Type"), selection: $deviceType) {
                            ForEach(RemoteDevice.DeviceType.allCases, id: \.self) { type in
                                Label(AppLocalization.string(type.rawValue), systemImage: type.systemIcon).tag(type)
                            }
                        }
                    }
                }

                Section(
                    header: Text(AppLocalization.string("Authentication")),
                    footer: Text(AppLocalization.string("Enter your Mac account username and password. Leave Username empty to use a VNC password."))
                ) {
                    TextField(AppLocalization.string("Username (Mac account, optional)"), text: $username)
                        .autocorrectionDisabled()
                        #if canImport(UIKit)
                        .textInputAutocapitalization(.never)
                        #endif
                    SecureField(AppLocalization.string(username.isEmpty ? "VNC Password (Optional)" : "Mac Account Password"), text: $password)
                }

                SSHConnectionFields(draft: $sshDraft, defaultServer: host,
                                    savedKeys: viewModel.savedSSHKeys, selectSavedKey: viewModel.selectSavedSSHKey,
                                    refreshSavedKeys: { _ = try viewModel.managedSSHKeys() })
                if let saveError {
                    Section { Text(saveError).foregroundStyle(.red) }
                }
                if isQuickConnect {
                    Section(footer: Text(AppLocalization.string("Save this computer and its password for future connections. Leave off for a temporary session."))) {
                        Toggle(AppLocalization.string("Save Computer"), isOn: $saveComputer)
                    }
                }

                if includesSavedDetails {
                    Section(
                        header: Text(AppLocalization.string("Wake-on-LAN (Optional)")),
                        footer: Text(AppLocalization.string("Enter the remote Mac's hardware MAC address (e.g. AA:BB:CC:DD:EE:FF) to wake it when sleeping."))
                    ) {
                        TextField(AppLocalization.string("MAC Address (Optional)"), text: $macAddress)
                            .autocorrectionDisabled()
                    }
                }
            }
            .formStyle(.grouped)
            #if canImport(UIKit)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .navigationTitle(AppLocalization.string(isQuickConnect ? "Quick Connect" : "Add Computer"))
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string(isQuickConnect ? "Connect" : "Save")) {
                        guard let request else { return }
                        do {
                            if let onQuickConnect {
                                try onQuickConnect(request, saveComputer)
                            } else {
                                try viewModel.saveConfiguredDevice(request.device, password: request.password,
                                                                  sshPassword: request.sshPassword, sshPrivateKey: request.sshPrivateKey)
                            }
                            dismiss()
                        } catch {
                            saveError = AppLocalization.string("Could not save the SSH credentials to Keychain. The computer was not saved.") + " " + error.localizedDescription
                        }
                    }
                    .disabled(request == nil)
                }
            }
        }
        #if os(macOS)
        .frame(width: 540, height: includesSavedDetails ? 660 : 480)
        #endif
    }
}
