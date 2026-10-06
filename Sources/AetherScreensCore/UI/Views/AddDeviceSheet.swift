import SwiftUI

enum ConnectionFormField: Hashable {
    case name, host, port, username, password, macAddress
}

struct ConnectionFormKeyboardDismissBar: View {
    let dismissKeyboard: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(AppLocalization.string("Done"), action: dismissKeyboard)
                .accessibilityIdentifier("connection-dismiss-keyboard")
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 16)
        .background(.bar)
    }
}

/// Sheet for adding a new remote computer manually.
public struct AddDeviceSheet: View {
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    @ObservedObject public var viewModel: DeviceListViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var host: String = ""
    @State private var portString: String = "5900"
    @State private var deviceType: RemoteDevice.DeviceType = .mac
    @State private var password: String = ""
    @State private var username: String = ""
    @State private var macAddress: String = ""
    @State private var saveComputer = false
    @State private var sshDraft = SSHConnectionDraft()
    @State private var saveError: String?
    @FocusState private var focusedField: ConnectionFormField?
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
        guard sshDraft.valid(defaultHost: host) else { return nil }
        return ConnectionRequest(host: host, port: portString, name: includesSavedDetails ? name : "",
                          username: username, password: password, type: deviceType,
                          macAddress: includesSavedDetails ? macAddress : "",
                          sshConfiguration: sshDraft.configuration(defaultHost: host), sshCredentials: sshDraft.credentials)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(AppLocalization.string("Device Information"))) {
                    if includesSavedDetails {
                        TextField(AppLocalization.string("Name (e.g. Studio Mac)"), text: $name)
                            .accessibilityLabel(AppLocalization.string("Name (e.g. Studio Mac)"))
                            .accessibilityIdentifier("connection-name")
                            .focused($focusedField, equals: .name)
                    }
                    TextField(AppLocalization.string("Tailscale IP / Host (e.g. 100.80.1.25)"), text: $host)
                        .accessibilityLabel(AppLocalization.string("Tailscale IP / Host (e.g. 100.80.1.25)"))
                        .accessibilityIdentifier("connection-host")
                        .focused($focusedField, equals: .host)
                        .autocorrectionDisabled()
                        #if canImport(UIKit)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                    LabeledContent(AppLocalization.string("Port")) {
                        TextField(AppLocalization.string("Port"), text: $portString)
                            .accessibilityLabel(AppLocalization.string("Port"))
                            .accessibilityIdentifier("connection-port")
                            .focused($focusedField, equals: .port)
                            .labelsHidden()
                            .accessibilityLabel(AppLocalization.string("Port"))
                            .frame(minWidth: 80)
                            .multilineTextAlignment(.trailing)
                            #if canImport(UIKit)
                            .keyboardType(.numberPad)
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
                        .accessibilityLabel(AppLocalization.string("Username (Mac account, optional)"))
                        .accessibilityIdentifier("connection-username")
                        .focused($focusedField, equals: .username)
                        .autocorrectionDisabled()
                        #if canImport(UIKit)
                        .textInputAutocapitalization(.never)
                        #endif
                    SecureField(AppLocalization.string(username.isEmpty ? "VNC Password (Optional)" : "Mac Account Password"), text: $password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(isQuickConnect ? .go : .done)
                        .onSubmit(submitConnection)
                }

                SSHConnectionForm(draft: $sshDraft, defaultHost: host)

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
                            .focused($focusedField, equals: .macAddress)
                            .autocorrectionDisabled()
                    }
                }
            }
            .formStyle(.grouped)
            #if canImport(UIKit)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                if focusedField != nil {
                    ConnectionFormKeyboardDismissBar { focusedField = nil }
                }
            }
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
                    Button(AppLocalization.string(isQuickConnect ? "Connect" : "Save"), action: submitConnection)
                    .disabled(request == nil)
                }
            }
        }
        .alert(AppLocalization.string("Unable to Save Connection"), isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button(AppLocalization.string("OK")) { saveError = nil }
        } message: { Text(AppLocalization.string(saveError ?? "")) }
        #if os(macOS)
        .frame(width: 540, height: includesSavedDetails || sshDraft.enabled ? 660 : 540)
        #endif
    }

    private func submitConnection() {
        guard let request else { return }
        do {
            if let onQuickConnect {
                try onQuickConnect(request, saveComputer)
            } else {
                try viewModel.saveConnection(request)
            }
            dismiss()
        } catch {
            saveError = "Could not save SSH credentials. Check the private key or unlock the device and try again."
        }
    }
}
