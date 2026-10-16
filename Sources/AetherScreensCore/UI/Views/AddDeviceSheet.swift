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
    @State private var remoteProtocol: RemoteDevice.RemoteProtocol = .rfb
    @State private var password: String = ""
    @State private var username: String = ""
    @State private var macAddress: String = ""
    @State private var isFavorite = false
    @State private var tagsString = ""
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
        let tags = tagsString
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return ConnectionRequest(host: host, port: portString, name: includesSavedDetails ? name : "",
                          username: username, password: password, type: deviceType,
                          remoteProtocol: remoteProtocol,
                          macAddress: includesSavedDetails ? macAddress : "",
                          ssh: sshDraft.settings, sshPassword: sshDraft.passwordToSave ?? "", sshPrivateKey: sshDraft.privateKeyToSave,
                          isFavorite: isFavorite, tags: tags)
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

                    if includesSavedDetails {
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
                    }
                }

                Section(
                    header: Text(AppLocalization.string(remoteProtocol == .rdp ? "Windows Authentication" : "Authentication")),
                    footer: Text(AppLocalization.string(remoteProtocol == .rdp
                        ? "Enter your Windows account username and password."
                        : "Enter your Mac account username and password. Leave Username empty to use a VNC password."))
                ) {
                    TextField(AppLocalization.string(remoteProtocol == .rdp ? "Windows Username" : "Username (Mac account, optional)"), text: $username)
                        .autocorrectionDisabled()
                        #if canImport(UIKit)
                        .textInputAutocapitalization(.never)
                        #endif
                    SecureField(AppLocalization.string(remoteProtocol == .rdp ? "Password" : (username.isEmpty ? "VNC Password (Optional)" : "Mac Account Password")), text: $password)
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
                    Section(header: Text(AppLocalization.string("Organization"))) {
                        Toggle(AppLocalization.string("Favorite"), isOn: $isFavorite)
                            .accessibilityIdentifier("add-favorite-toggle")
                        TextField(AppLocalization.string("Tags (comma separated, e.g. Home, Work)"), text: $tagsString)
                            .accessibilityIdentifier("add-tags-input")
                            .autocorrectionDisabled()
                            #if canImport(UIKit)
                            .textInputAutocapitalization(.never)
                            #endif
                    }

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
