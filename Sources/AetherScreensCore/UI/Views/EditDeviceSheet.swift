import SwiftUI

/// Sheet for editing an existing computer's connection details, VNC password, and Wake-on-LAN settings.
public struct EditDeviceSheet: View {
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    public let device: RemoteDevice
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
    @State private var isPasswordModified: Bool = false
    @State private var disconnectAction: DisconnectAction = .none
    @State private var sshDraft = SSHConnectionDraft()
    @State private var saveError: String?

    public init(device: RemoteDevice, viewModel: DeviceListViewModel) {
        self.device = device
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(AppLocalization.string("Device Information"))) {
                    TextField(AppLocalization.string("Name"), text: $name)
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

                Section(header: Text(AppLocalization.string("Operating System"))) {
                    Picker(AppLocalization.string("Device Type"), selection: $deviceType) {
                        ForEach(RemoteDevice.DeviceType.allCases, id: \.self) { type in
                            Label(AppLocalization.string(type.rawValue), systemImage: type.systemIcon).tag(type)
                        }
                    }
                }

                Section(header: Text(AppLocalization.string("On Disconnect")),
                        footer: Text(AppLocalization.string(disconnectAction == .logOut
                            ? "Logs out the remote user immediately when you disconnect. Save your work first."
                            : "Runs only when you choose Disconnect. Hot corners use the remote Mac's configured actions."))) {
                    Picker(AppLocalization.string("Perform Action"), selection: $disconnectAction) {
                        ForEach(DisconnectAction.allCases.filter { $0.isSupported(on: deviceType) }) { action in
                            Text(AppLocalization.string(action.titleKey)).tag(action)
                        }
                    }
                    .accessibilityIdentifier("disconnect-action")
                    .accessibilityValue(AppLocalization.string(disconnectAction.titleKey))
                }
                .onChange(of: deviceType) { _, type in
                    if !disconnectAction.isSupported(on: type) { disconnectAction = .none }
                }

                Section(
                    header: Text(AppLocalization.string("Authentication")),
                    footer: Text(AppLocalization.string("Saved in the system Keychain. Enter a new password to update or leave unchanged."))
                ) {
                    TextField(AppLocalization.string("Username (Mac account, optional)"), text: $username)
                        .autocorrectionDisabled()
                        #if canImport(UIKit)
                        .textInputAutocapitalization(.never)
                        #endif
                    SecureField(AppLocalization.string(username.isEmpty ? "VNC Password" : "Mac Account Password"), text: $password)
                        .onChange(of: password) { _, _ in
                            isPasswordModified = true
                        }
                }

                SSHConnectionFields(draft: $sshDraft, defaultServer: host,
                                    savedKeys: viewModel.savedSSHKeys, selectSavedKey: viewModel.selectSavedSSHKey,
                                    refreshSavedKeys: { _ = try viewModel.managedSSHKeys() })
                if let saveError { Section { Text(saveError).foregroundStyle(.red) } }
                Section(
                    header: Text(AppLocalization.string("Wake-on-LAN (Optional)")),
                    footer: Text(AppLocalization.string("Hardware MAC address (e.g. AA:BB:CC:DD:EE:FF) to wake this Mac remotely."))
                ) {
                    TextField(AppLocalization.string("MAC Address"), text: $macAddress)
                        .autocorrectionDisabled()
                }
            }
            .formStyle(.grouped)
            #if canImport(UIKit)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .navigationTitle(AppLocalization.string("Edit Computer"))
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
                    Button(AppLocalization.string("Save")) {
                        guard let port = UInt16(portString), port > 0 else { return }
                        var updatedDev = device
                        updatedDev.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? host : name
                        updatedDev.host = host.trimmingCharacters(in: .whitespaces)
                        updatedDev.port = port
                        updatedDev.username = username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : username.trimmingCharacters(in: .whitespacesAndNewlines)
                        updatedDev.authMethod = updatedDev.username == nil ? .vncPassword : .macAccount
                        updatedDev.deviceType = deviceType
                        updatedDev.macAddress = macAddress.isEmpty ? nil : macAddress
                        updatedDev.ssh = sshDraft.settings
                        
                        let newPassword = isPasswordModified ? (password.isEmpty ? nil : password) : DeviceStore.shared.getPassword(for: device)
                        
                        do {
                            try viewModel.saveConfiguredDevice(updatedDev, password: newPassword,
                                                               sshPassword: sshDraft.passwordToSave, sshPrivateKey: sshDraft.privateKeyToSave)
                        } catch {
                            saveError = AppLocalization.string("Could not save the SSH credentials to Keychain. The computer was not saved.") + " " + error.localizedDescription
                            return
                        }
                        DisconnectActionStore.shared.save(disconnectAction, for: device.id)
                        viewModel.reload()
                        dismiss()
                    }
                    .disabled(!sshDraft.isValid || host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || UInt16(portString) == nil || UInt16(portString) == 0)
                }
            }
            .onAppear {
                username = device.username ?? ""
                sshDraft = SSHConnectionDraft(settings: device.ssh)
                do {
                    let fingerprint = try viewModel.sshKeyFingerprint(for: device.ssh)
                    sshDraft = SSHConnectionDraft(settings: device.ssh, keyFingerprint: fingerprint)
                } catch {
                    saveError = (error as? SSHPrivateKey.Failure)?.errorDescription
                        ?? AppLocalization.string("Could not read the saved SSH key from Keychain.")
                }
                name = device.name
                host = device.host
                portString = "\(device.port)"
                deviceType = device.deviceType
                disconnectAction = DisconnectActionStore.shared.load(for: device.id, type: device.deviceType)
                macAddress = device.macAddress ?? ""
                if let savedPwd = DeviceStore.shared.getPassword(for: device) {
                    password = savedPwd
                }
                isPasswordModified = false
            }
        }
        #if os(macOS)
        .frame(width: 540, height: 660)
        #endif
    }
}
