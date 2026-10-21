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
    @State private var remoteProtocol: RemoteDevice.RemoteProtocol = .rfb
    @State private var password: String = ""
    @State private var username: String = ""
    @State private var macAddress: String = ""
    @State private var isPasswordModified: Bool = false
    @State private var disconnectAction: DisconnectAction = .none
    @State private var isFavorite: Bool = false
    @State private var tagsString: String = ""
    @State private var desktopResolution: String = "1920x1080"
    @State private var remoteAudioEnabled: Bool = true
    @State private var autoFitResolution: Bool = false
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
                            .onChange(of: portString) { _, newPort in
                                if newPort == "3389" && remoteProtocol == .rfb {
                                    remoteProtocol = .rdp
                                    if deviceType == .mac { deviceType = .windows }
                                } else if newPort == "5900" && remoteProtocol == .rdp {
                                    remoteProtocol = .rfb
                                }
                            }
                    }
                }

                Section(header: Text(AppLocalization.string("Organization"))) {
                    Toggle(AppLocalization.string("Favorite"), isOn: $isFavorite)
                        .accessibilityIdentifier("edit-favorite-toggle")
                    TextField(AppLocalization.string("Tags (comma separated, e.g. Home, Work)"), text: $tagsString)
                        .accessibilityIdentifier("edit-tags-input")
                        .autocorrectionDisabled()
                        #if canImport(UIKit)
                        .textInputAutocapitalization(.never)
                        #endif
                }

                Section(header: Text(AppLocalization.string("Protocol & System"))) {
                    Picker(AppLocalization.string("Protocol"), selection: $remoteProtocol) {
                        Text(AppLocalization.string("macOS / VNC (RFB)")).tag(RemoteDevice.RemoteProtocol.rfb)
                        Text(AppLocalization.string("Windows Remote Desktop (RDP)")).tag(RemoteDevice.RemoteProtocol.rdp)
                    }
                    .accessibilityIdentifier("protocol-picker")
                    .onChange(of: remoteProtocol) { _, newProto in
                        if newProto == .rdp && (portString == "5900" || portString.isEmpty) {
                            portString = "3389"
                            if deviceType == .mac { deviceType = .windows }
                        } else if newProto == .rfb && (portString == "3389" || portString.isEmpty) {
                            portString = "5900"
                        }
                    }

                    Picker(AppLocalization.string("Device Type"), selection: $deviceType) {
                        ForEach(RemoteDevice.DeviceType.allCases, id: \.self) { type in
                            Label(AppLocalization.string(type.rawValue), systemImage: type.systemIcon).tag(type)
                        }
                    }
                    .onChange(of: deviceType) { _, newType in
                        if newType == .windows && remoteProtocol == .rfb {
                            remoteProtocol = .rdp
                            if portString == "5900" || portString.isEmpty { portString = "3389" }
                        }
                    }

                    if remoteProtocol == .rdp {
                        Picker(AppLocalization.string("Resolution"), selection: $desktopResolution) {
                            Text(AppLocalization.string("1920 × 1080 (1080p Full HD)")).tag("1920x1080")
                            Text(AppLocalization.string("2560 × 1440 (2K QHD)")).tag("2560x1440")
                            Text(AppLocalization.string("1680 × 1050 (16:10)")).tag("1680x1050")
                            Text(AppLocalization.string("1280 × 720 (720p HD)")).tag("1280x720")
                            Text(AppLocalization.string("3840 × 2160 (4K UHD)")).tag("3840x2160")
                        }
                        Toggle(AppLocalization.string("Auto-Fit Resolution"), isOn: $autoFitResolution)
                        Toggle(AppLocalization.string("Remote Audio Playback"), isOn: $remoteAudioEnabled)
                    }
                }

                Section(header: Text(AppLocalization.string("On Disconnect")),
                        footer: Text(AppLocalization.string(disconnectAction == .logOut
                            ? "Logs out the remote user immediately when you disconnect. Save your work first."
                            : "Runs only when you choose Disconnect. Hot corners use the remote Mac's configured actions.")).formFooterStyle()) {
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
                    header: Text(AppLocalization.string(remoteProtocol == .rdp ? "Windows Authentication" : "Authentication")),
                    footer: Text(AppLocalization.string("Saved in the system Keychain. Enter a new password to update or leave unchanged.")).formFooterStyle()
                ) {
                    TextField(AppLocalization.string(remoteProtocol == .rdp ? "Windows Username" : "Username (Mac account, optional)"), text: $username)
                        .autocorrectionDisabled()
                        #if canImport(UIKit)
                        .textInputAutocapitalization(.never)
                        #endif
                    SecureField(AppLocalization.string(remoteProtocol == .rdp ? "Password" : (username.isEmpty ? "VNC Password" : "Mac Account Password")), text: $password)
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
                    footer: Text(AppLocalization.string("Hardware MAC address (e.g. AA:BB:CC:DD:EE:FF) to wake this Mac remotely.")).formFooterStyle()
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
                        updatedDev.remoteProtocol = remoteProtocol
                        if remoteProtocol == .rdp {
                            updatedDev.authMethod = .windowsCredentials
                            let dims = desktopResolution.split(separator: "x").compactMap { Int($0) }
                            updatedDev.desktopWidth = dims.count == 2 ? dims[0] : 1920
                            updatedDev.desktopHeight = dims.count == 2 ? dims[1] : 1080
                            updatedDev.remoteAudioEnabled = remoteAudioEnabled
                            updatedDev.autoFitResolution = autoFitResolution
                        } else {
                            updatedDev.authMethod = updatedDev.username == nil ? .vncPassword : .macAccount
                            updatedDev.desktopWidth = nil
                            updatedDev.desktopHeight = nil
                            updatedDev.remoteAudioEnabled = nil
                            updatedDev.autoFitResolution = nil
                        }
                        updatedDev.deviceType = deviceType
                        updatedDev.macAddress = macAddress.isEmpty ? nil : macAddress
                        updatedDev.ssh = sshDraft.settings
                        updatedDev.isFavorite = isFavorite
                        updatedDev.tags = tagsString
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        
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
                remoteProtocol = device.remoteProtocol
                if let dw = device.desktopWidth, let dh = device.desktopHeight {
                    desktopResolution = "\(dw)x\(dh)"
                } else {
                    desktopResolution = "1920x1080"
                }
                remoteAudioEnabled = device.remoteAudioEnabled ?? true
                autoFitResolution = device.autoFitResolution ?? false
                disconnectAction = DisconnectActionStore.shared.load(for: device.id, type: device.deviceType)
                macAddress = device.macAddress ?? ""
                isFavorite = device.isFavorite
                tagsString = device.tags.joined(separator: ", ")
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
