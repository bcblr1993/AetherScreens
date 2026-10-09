import SwiftUI
import UniformTypeIdentifiers

struct SSHConnectionFields: View {
    @Binding var draft: SSHConnectionDraft
    let defaultServer: String
    var savedKeys: [DeviceListViewModel.SavedSSHKey] = []
    var selectSavedKey: ((DeviceListViewModel.SavedSSHKey, inout SSHConnectionDraft) throws -> Void)? = nil
    var refreshSavedKeys: (() throws -> Void)? = nil
    @FocusState private var focusedField: String?
    @State private var importingKey = false
    @State private var encryptedImport: EncryptedSSHKeyImport?
    @State private var choosingSavedKey = false
    @State private var keyError: String?
    @State private var savedKeysError: String?
    @State private var didRefreshSavedKeys = false

    var body: some View {
        Section(header: Text(AppLocalization.string("Secure Connection")),
                footer: Text(AppLocalization.string("SSH encrypts the connection. The SSH account is separate from the remote desktop account. Leave the password empty to keep a saved password or enter it when connecting."))) {
            Toggle(AppLocalization.string("Use SSH Tunnel"), isOn: $draft.enabled)
                .accessibilityIdentifier("ssh-enabled")
                .onChange(of: draft.enabled) { _, enabled in
                    if enabled && draft.serverHost.isEmpty { draft.serverHost = defaultServer }
                }
            if draft.enabled {
                addressField("SSH Server", text: $draft.serverHost, identifier: "ssh-server")
                LabeledContent(AppLocalization.string("SSH Port")) {
                    PortTextField(text: $draft.port, label: "SSH Port", identifier: "ssh-port")
                        .frame(minWidth: 80)
                        #if canImport(UIKit)
                        .frame(minHeight: 44)
                        #endif
                        .accessibilityIdentifier("ssh-port")
                }
                addressField("SSH Username", text: $draft.username, identifier: "ssh-username")
                Picker(AppLocalization.string("SSH Authentication"), selection: $draft.authenticationMode) {
                    Text(AppLocalization.string("Password")).tag(SSHConnectionDraft.AuthenticationMode.password)
                    Text(AppLocalization.string("Private Key")).tag(SSHConnectionDraft.AuthenticationMode.privateKey)
                }
                .accessibilityIdentifier("ssh-authentication-method")
                .onAppear {
                    if draft.authenticationMode == .privateKey && !didRefreshSavedKeys {
                        didRefreshSavedKeys = true
                        refreshKeys()
                    }
                }
                .onChange(of: draft.authenticationMode) { _, mode in
                    if mode == .privateKey {
                        didRefreshSavedKeys = true
                        refreshKeys()
                    }
                }
                if draft.authenticationMode == .privateKey {
                    if !savedKeys.isEmpty, let selectSavedKey {
                        Button(AppLocalization.string("Use Saved Private Key")) {
                            focusedField = nil
                            choosingSavedKey = true
                        }
                        .accessibilityIdentifier("ssh-saved-key")
                        .confirmationDialog(AppLocalization.string("Use Saved Private Key"), isPresented: $choosingSavedKey, titleVisibility: .visible) {
                            ForEach(savedKeys) { key in
                                Button(key.name) {
                                    do {
                                        try selectSavedKey(key, &draft)
                                        keyError = nil
                                        savedKeysError = nil
                                    } catch {
                                        keyError = (error as? SSHPrivateKey.Failure)?.errorDescription
                                            ?? AppLocalization.string("Could not read the saved SSH key from Keychain.")
                                    }
                                }
                                .accessibilityIdentifier("ssh-saved-key-option-" + key.id.uuidString)
                            }
                            Button(AppLocalization.string("Cancel"), role: .cancel) {}
                        }
                    }
                    Button(AppLocalization.string(draft.keyReference == nil ? "Import Private Key" : "Replace Private Key")) {
                        focusedField = nil
                        importingKey = true
                    }
                    .accessibilityIdentifier("ssh-import-key")
                    .sheet(item: $encryptedImport) { request in
                        SSHKeyUnlockSheet(request: request) { normalized in
                            try draft.importPrivateKey(normalized)
                            keyError = nil
                        }
                    }
                    HStack {
                        Text(AppLocalization.string("Paste Private Key"))
                        Spacer()
                        PasteButton(payloadType: String.self) { values in
                            focusedField = nil
                            do {
                                guard let value = values.first else { throw SSHPrivateKey.Failure.invalid }
                                guard value.utf8.count <= SSHPrivateKey.maximumSize else { throw SSHPrivateKey.Failure.tooLarge }
                                try importKey(Data(value.utf8))
                                keyError = nil
                            } catch {
                                keyError = (error as? SSHPrivateKey.Failure)?.errorDescription
                                    ?? AppLocalization.string("Could not read the SSH key file.")
                            }
                        }
                        .fixedSize()
                        .accessibilityIdentifier("ssh-paste-key")
                        .accessibilityLabel(AppLocalization.string("Paste Private Key"))
                    }
                    .accessibilityElement(children: .contain)
                    if let fingerprint = draft.keyFingerprint {
                        Text(fingerprint).font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    } else if draft.keyReference != nil {
                        Text(AppLocalization.string("Saved private key")).foregroundStyle(.secondary)
                    }
                    Text(AppLocalization.string("Import an Ed25519 or ECDSA key, including encrypted ECDSA PKCS#8. Saved keys stay in Keychain; temporary keys remain in this session."))
                        .font(.caption).foregroundStyle(.secondary)
                    if let keyError { Text(keyError).foregroundStyle(.red) }
                    if let savedKeysError {
                        Text(savedKeysError).foregroundStyle(.red)
                        Button(AppLocalization.string("Retry")) { refreshKeys() }
                    }
                } else {
                    SecureField(AppLocalization.string("SSH Password (Optional)"), text: $draft.password)
                        .focused($focusedField, equals: "password")
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                        .accessibilityIdentifier("ssh-settings-password")
                }
                addressField("Desktop Host from SSH Server", text: $draft.remoteHost, identifier: "ssh-desktop-host")
            }
        }
        .fileImporter(isPresented: $importingKey, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let file = try FileHandle(forReadingFrom: url)
                defer { try? file.close() }
                let data = try file.read(upToCount: SSHPrivateKey.maximumSize + 1) ?? Data()
                try importKey(data)
                keyError = nil
            } catch {
                if let cocoa = error as? CocoaError, cocoa.code == .userCancelled { return }
                // Do not expose file paths or imported data in the sheet.
                keyError = (error as? SSHPrivateKey.Failure)?.errorDescription
                    ?? AppLocalization.string("Could not read the SSH key file.")
            }
        }
    }

    private func importKey(_ data: Data) throws {
        if let request = try EncryptedSSHKeyImport.request(for: data) {
            encryptedImport = request
        } else {
            try draft.importPrivateKey(data)
        }
    }

    private func refreshKeys() {
        do { try refreshSavedKeys?(); savedKeysError = nil }
        catch { savedKeysError = AppLocalization.string("Could not read the saved SSH key from Keychain.") }
    }

    private func addressField(_ title: String, text: Binding<String>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppLocalization.string(title))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(AppLocalization.string(title), text: text)
                .focused($focusedField, equals: identifier)
                .submitLabel(.done)
                .onSubmit { focusedField = nil }
                .autocorrectionDisabled()
                #if canImport(UIKit)
                .textInputAutocapitalization(.never)
                #endif
                .accessibilityIdentifier(identifier)
        }
    }
}
