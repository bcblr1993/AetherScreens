import SwiftUI
import AetherScreensSSH

/// Sheet for editing an existing computer's connection details, VNC password, and Wake-on-LAN settings.
public struct EditDeviceSheet: View {
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    public let device: RemoteDevice
    @ObservedObject public var viewModel: DeviceListViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var host: String = ""
    @State private var portString: String = "5900"
    @State private var deviceType: RemoteDevice.DeviceType = .mac
    @State private var password: String = ""
    @State private var username: String = ""
    @State private var macAddress: String = ""
    @State private var isPasswordModified: Bool = false
    @State private var cursorSpeed: Double = 1
    @State private var sharedClipboard = true
    @State private var imageCompression: RemoteImageCompressionPolicy = .never
    @State private var sshDraft = SSHConnectionDraft()
    @State private var saveError: String?
    @State private var rememberedSSHIdentity: SSHHostKeyIdentity?
    @State private var showingForgetSSHIdentity = false
    @State private var forgettingSSHIdentity = false
    @State private var trustError: String?
    @State private var disconnectAction: RemoteDisconnectAction = .disconnectOnly
    @State private var shortcutEnabled = false
    @State private var shortcutAlias = ""
    @State private var widgetEnabled = false
    @State private var widgetAlias = ""
    @State private var initialWidgetEnabled = false
    @State private var initialWidgetAlias = ""
    @State private var widgetUnavailable = false
    @FocusState private var focusedField: ConnectionFormField?

    public init(device: RemoteDevice, viewModel: DeviceListViewModel) {
        self.device = device
        self.viewModel = viewModel
    }

    private var widgetPreferencesChanged: Bool {
        !widgetUnavailable && (widgetEnabled != initialWidgetEnabled
            || (widgetEnabled && widgetAlias != initialWidgetAlias))
    }

    private func reloadWidgetPreferences() {
        guard let catalog = viewModel.widgetCatalogStore else { return }
        do {
            try catalog.reloadForEditing()
            let entry = catalog.entry(for: device.id)
            widgetEnabled = entry != nil
            widgetAlias = entry?.alias ?? device.name
            initialWidgetEnabled = widgetEnabled
            initialWidgetAlias = widgetAlias
            widgetUnavailable = false
        } catch {
            widgetUnavailable = true
        }
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(AppLocalization.string("Device Information"))) {
                    TextField(AppLocalization.string("Name"), text: $name)
                        .focused($focusedField, equals: .name)
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

                Section(header: Text(AppLocalization.string("Operating System"))) {
                    Picker(AppLocalization.string("Device Type"), selection: $deviceType) {
                        ForEach(RemoteDevice.DeviceType.allCases, id: \.self) { type in
                            Label(AppLocalization.string(type.rawValue), systemImage: type.systemIcon).tag(type)
                        }
                    }
                }

                Section(
                    header: Text(AppLocalization.string("Authentication")),
                    footer: Text(AppLocalization.string("Saved in the system Keychain. Enter a new password to update or leave unchanged."))
                ) {
                    TextField(AppLocalization.string("Username (Mac account, optional)"), text: $username)
                        .accessibilityLabel(AppLocalization.string("Username (Mac account, optional)"))
                        .accessibilityIdentifier("connection-username")
                        .focused($focusedField, equals: .username)
                        .autocorrectionDisabled()
                        #if canImport(UIKit)
                        .textInputAutocapitalization(.never)
                        #endif
                    SecureField(AppLocalization.string(username.isEmpty ? "VNC Password" : "Mac Account Password"), text: $password)
                        .focused($focusedField, equals: .password)
                        .onChange(of: password) { _, _ in
                            isPasswordModified = true
                        }
                }

                SSHConnectionForm(draft: $sshDraft, defaultHost: host)

                if viewModel.shortcutCatalogStore != nil {
                    Section(
                        header: Text(AppLocalization.string("Shortcuts")),
                        footer: Text(AppLocalization.string("Only the alias you choose is shared with Shortcuts. Connection details and passwords stay in AetherScreens."))
                    ) {
                        Toggle(AppLocalization.string("Show in Shortcuts"), isOn: $shortcutEnabled)
                            .accessibilityIdentifier("device-shortcut-enabled")
                        if shortcutEnabled {
                            TextField(AppLocalization.string("Shortcut Alias"), text: $shortcutAlias)
                                .accessibilityIdentifier("device-shortcut-alias")
                                .autocorrectionDisabled()
                        }
                    }
                }

                if viewModel.widgetCatalogStore != nil {
                    Section(
                        header: Text(AppLocalization.string("Widgets")),
                        footer: Text(AppLocalization.string("Only the alias you choose is shared with Widgets. Connection details and passwords stay in AetherScreens."))
                    ) {
                        if widgetUnavailable {
                            Text(AppLocalization.string("Widgets are unavailable. Open the app and try again."))
                            Button(AppLocalization.string("Try Again"), action: reloadWidgetPreferences)
                        } else {
                            Toggle(AppLocalization.string("Show in Widgets"), isOn: $widgetEnabled)
                                .accessibilityIdentifier("device-widget-enabled")
                            if widgetEnabled {
                                TextField(AppLocalization.string("Widget Alias"), text: $widgetAlias)
                                    .accessibilityIdentifier("device-widget-alias")
                                    .autocorrectionDisabled()
                            }
                        }
                    }
                }

                if sshDraft.enabled, let identity = rememberedSSHIdentity,
                   let configuration = device.sshConfiguration {
                    Section(AppLocalization.string("Trusted SSH Server")) {
                        LabeledContent(AppLocalization.string("Address"), value: configuration.host)
                        LabeledContent(AppLocalization.string("Port"), value: String(configuration.port))
                        Text(identity.fingerprint)
                            .accessibilityLabel(identity.fingerprint)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("ssh-saved-fingerprint")
                        Button(AppLocalization.string("Forget Trusted Server"), role: .destructive) {
                            showingForgetSSHIdentity = true
                        }
                        .frame(minHeight: 44)
                        .disabled(forgettingSSHIdentity)
                        .accessibilityIdentifier("ssh-forget-trust")
                        if forgettingSSHIdentity { ProgressView() }
                    }
                }

                Section(AppLocalization.string("Controls")) {
                    Toggle(AppLocalization.string("Use Shared Clipboard"), isOn: $sharedClipboard)
                        .accessibilityIdentifier("device-shared-clipboard")
                    LabeledContent(AppLocalization.string("Cursor Speed"), value: AppLocalization.format("%.2f×", cursorSpeed))
                    Slider(value: $cursorSpeed, in: 0.25...2, step: 0.25)
                        .accessibilityLabel(AppLocalization.string("Cursor Speed"))
                        .accessibilityIdentifier("cursor-speed-slider")
                    if deviceType == .mac {
                        Picker(AppLocalization.string("Image Compression"), selection: $imageCompression) {
                            ForEach(RemoteImageCompressionPolicy.allCases) { policy in
                                Text(AppLocalization.string(policy.rawValue)).tag(policy)
                            }
                        }
                        .accessibilityIdentifier("device-image-compression")
                        Text(AppLocalization.string("Image compression halves the width and height. Remote-only keeps full resolution on the same LAN or when the network route cannot be determined."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if deviceType == .mac {
                    Section(
                        header: Text(AppLocalization.string("When Disconnecting")),
                        footer: Text(AppLocalization.string(disconnectAction == .logOut
                            ? "Logging out closes remote apps. Save your work first."
                            : "Runs when you close a control session. Observe sessions and interrupted connections do not run this action. Hot corners must be configured on the remote Mac."))
                    ) {
                        Picker(AppLocalization.string("Action"), selection: $disconnectAction) {
                            ForEach(RemoteDisconnectAction.allCases) { action in
                                Text(AppLocalization.string(action.rawValue)).tag(action)
                            }
                        }
                        .accessibilityIdentifier("disconnect-action-picker")
                        .pickerStyle(.menu)
                    }
                }

                Section(
                    header: Text(AppLocalization.string("Wake-on-LAN (Optional)")),
                    footer: Text(AppLocalization.string("Hardware MAC address (e.g. AA:BB:CC:DD:EE:FF) to wake this Mac remotely."))
                ) {
                    TextField(AppLocalization.string("MAC Address"), text: $macAddress)
                        .focused($focusedField, equals: .macAddress)
                        .autocorrectionDisabled()
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
                        if widgetPreferencesChanged && widgetEnabled, let catalog = viewModel.widgetCatalogStore {
                            do { try catalog.validateAlias(widgetAlias, for: device.id) }
                            catch WidgetCatalogStore.Failure.invalidAlias {
                                saveError = "Enter a Widget alias of 1–80 characters without control characters."
                                return
                            } catch {
                                saveError = "Widgets are unavailable. Open the app and try again."
                                return
                            }
                        }
                        if shortcutEnabled, let catalog = viewModel.shortcutCatalogStore {
                            do { try catalog.validateAlias(shortcutAlias, for: device.id) }
                            catch ShortcutCatalogStore.Failure.invalidAlias {
                                saveError = "Enter a shortcut alias of 1–80 characters without control characters."
                                return
                            } catch {
                                saveError = "Too many computers are enabled in Shortcuts. Disable one and try again."
                                return
                            }
                        }
                        var updatedDev = device
                        updatedDev.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? host : name
                        updatedDev.host = host.trimmingCharacters(in: .whitespaces)
                        updatedDev.port = port
                        updatedDev.username = username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : username.trimmingCharacters(in: .whitespacesAndNewlines)
                        updatedDev.authMethod = updatedDev.username == nil ? .vncPassword : .macAccount
                        updatedDev.deviceType = deviceType
                        updatedDev.cursorSpeed = cursorSpeed == 1 ? nil : cursorSpeed
                        updatedDev.sharedClipboard = sharedClipboard ? nil : false
                        updatedDev.imageCompression = imageCompression == .never ? nil : imageCompression
                        updatedDev.macAddress = macAddress.isEmpty ? nil : macAddress
                        updatedDev.disconnectAction = deviceType == .mac && disconnectAction != .disconnectOnly ? disconnectAction : nil
                        
                        let newPassword = isPasswordModified ? (password.isEmpty ? nil : password) : DeviceStore.shared.getPassword(for: device)
                        
                        updatedDev.sshConfiguration = sshDraft.configuration(defaultHost: host)
                        do {
                            try viewModel.updateConnection(updatedDev, password: newPassword, sshCredentials: sshDraft.credentials)
                            if shortcutEnabled {
                                try viewModel.shortcutCatalogStore?.setAlias(shortcutAlias, for: device.id)
                            } else {
                                viewModel.shortcutCatalogStore?.remove(id: device.id)
                                ShortcutLaunchQueue.shared.cancel(deviceID: device.id)
                            }
                            if widgetPreferencesChanged {
                                if widgetEnabled {
                                    try viewModel.widgetCatalogStore?.setAlias(widgetAlias, for: device.id)
                                } else {
                                    try viewModel.widgetCatalogStore?.remove(id: device.id)
                                    ShortcutLaunchQueue.widgets.cancel(deviceID: device.id)
                                }
                            }
                            dismiss()
                        } catch is WidgetCatalogStore.Failure {
                            saveError = "Connection settings were saved, but Widgets were not updated. Please try again."
                        } catch SSHKeychainStore.Failure.credentialMismatch {
                            saveError = "Enter new SSH credentials after changing the server, account, or authentication method."
                        } catch {
                            saveError = "Could not save SSH credentials. Check the private key or unlock the device and try again."
                        }
                    }
                    .disabled(forgettingSSHIdentity || host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || UInt16(portString) == nil || UInt16(portString) == 0 || !sshDraft.valid(defaultHost: host, editing: true))
                }
            }
            .onAppear {
                username = device.username ?? ""
                let shortcut = viewModel.shortcutCatalogStore?.entry(for: device.id)
                shortcutEnabled = shortcut != nil
                shortcutAlias = shortcut?.alias ?? device.name
                reloadWidgetPreferences()
                name = device.name
                host = device.host
                portString = "\(device.port)"
                deviceType = device.deviceType
                cursorSpeed = device.effectiveCursorSpeed
                sharedClipboard = device.effectiveSharedClipboard
                imageCompression = device.effectiveImageCompression
                disconnectAction = device.disconnectAction ?? .disconnectOnly
                macAddress = device.macAddress ?? ""
                if let savedPwd = DeviceStore.shared.getPassword(for: device) {
                    password = savedPwd
                }
                if let configuration = device.sshConfiguration {
                    sshDraft.enabled = true
                    sshDraft.host = configuration.host
                    sshDraft.port = String(configuration.port)
                    sshDraft.username = configuration.username
                    sshDraft.authentication = configuration.authentication
                    sshDraft.destinationHost = configuration.destinationHost
                    // No secret is loaded into a displayed editing field.
                    sshDraft.keepSavedCredential = true
                }
                isPasswordModified = false
            }
        }
        .task(id: device.id) {
            do {
                let identity = try await viewModel.loadTrustedSSHIdentity(for: device)
                guard !Task.isCancelled else { return }
                rememberedSSHIdentity = identity
            } catch {
                guard !Task.isCancelled else { return }
                trustError = "Could not read the trusted SSH server. Unlock the device and try again."
            }
        }
        .alert(AppLocalization.string("Forget Trusted SSH Server?"), isPresented: $showingForgetSSHIdentity) {
            Button(AppLocalization.string("Cancel"), role: .cancel) { }
            Button(AppLocalization.string("Forget"), role: .destructive) {
                guard let identity = rememberedSSHIdentity else { return }
                guard !forgettingSSHIdentity else { return }
                forgettingSSHIdentity = true
                Task {
                    defer { forgettingSSHIdentity = false }
                    do {
                        try await viewModel.forgetReviewedSSHIdentity(for: device, matching: identity)
                        rememberedSSHIdentity = nil
                    } catch {
                        trustError = "Could not forget the trusted SSH server. Its identity or saved connection may have changed. Unlock the device and try again."
                    }
                }
            }
            .accessibilityIdentifier("ssh-confirm-forget-trust")
        } message: {
            Text(AppLocalization.string("The next connection must verify the server fingerprint again. This affects all saved computers using the same SSH server and port. Existing connected sessions stay open."))
        }
        .alert(AppLocalization.string("SSH Server Trust"), isPresented: Binding(get: { trustError != nil }, set: { if !$0 { trustError = nil } })) {
            Button(AppLocalization.string("OK")) { trustError = nil }
        } message: { Text(AppLocalization.string(trustError ?? "")) }
        .alert(AppLocalization.string("Unable to Save Connection"), isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button(AppLocalization.string("OK")) { saveError = nil }
        } message: { Text(AppLocalization.string(saveError ?? "")) }
        #if os(macOS)
        .frame(width: 540, height: 660)
        #endif
    }
}
