import SwiftUI
import AetherScreensSSH
import UniformTypeIdentifiers

/// Shared transient draft for Add/Edit. Secrets never enter device metadata.
struct SSHConnectionDraft {
    var enabled = false
    var host = ""
    var port = "22"
    var username = ""
    var authentication: SSHConfiguration.Authentication = .password
    var password = ""
    var privateKey = ""
    var passphrase = ""
    var destinationHost = "127.0.0.1"
    var keepSavedCredential = false

    func configuration(defaultHost: String) -> SSHConfiguration? {
        guard enabled, let number = UInt16(port.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let endpoint = host.trimmingCharacters(in: .whitespacesAndNewlines)
        return try? SSHConfiguration(host: endpoint.isEmpty ? defaultHost.trimmingCharacters(in: .whitespacesAndNewlines) : endpoint,
                                     port: number, username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                                     authentication: authentication,
                                     destinationHost: destinationHost.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var credentials: SSHSessionCredentials? {
        guard enabled else { return nil }
        switch authentication {
        case .password: return password.isEmpty ? nil : .password(password)
        case .ed25519:
            return privateKey.isEmpty ? nil : .ed25519PrivateKey(privateKey, passphrase: passphrase.isEmpty ? nil : passphrase)
        }
    }

    mutating func importPrivateKey(_ data: Data) throws {
        guard !data.isEmpty, data.count <= 65_536,
              let key = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
        try SSHPrivateKeyCost.validate(key)
        privateKey = key
        passphrase = ""
    }

    static func readPrivateKey(from url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        // Bound the actual stream, not file metadata which can change between
        // inspection and reading. The extra byte detects an oversized file.
        while data.count < 65_537 {
            guard let block = try handle.read(upToCount: 65_537 - data.count), !block.isEmpty else { break }
            data.append(block)
        }
        guard !data.isEmpty, data.count <= 65_536 else { throw CocoaError(.fileReadCorruptFile) }
        return data
    }

    func valid(defaultHost: String, editing: Bool = false) -> Bool {
        !enabled || (configuration(defaultHost: defaultHost) != nil && (credentials != nil || (editing && keepSavedCredential)))
    }
}

struct SSHConnectionForm: View {
    @Binding var draft: SSHConnectionDraft
    let defaultHost: String
    @State private var importingKey = false
    @State private var keyFileName: String?
    @State private var importFailed = false
    @State private var importInProgress = false
    @State private var importGeneration = UUID()

    var body: some View {
        Section(header: Text(AppLocalization.string("Secure Connection")),
                footer: Text(AppLocalization.string("SSH credentials are separate from your Mac account or VNC password. You will review the server fingerprint before connecting."))) {
            Toggle(AppLocalization.string("Use SSH Tunnel"), isOn: $draft.enabled)
                .accessibilityIdentifier("ssh-enabled")
            if draft.enabled {
                TextField(AppLocalization.string("SSH Host (blank uses computer address)"), text: $draft.host)
                    .accessibilityIdentifier("ssh-host")
                    .autocorrectionDisabled()
                TextField(AppLocalization.string("SSH Port"), text: $draft.port)
                    .accessibilityIdentifier("ssh-port")
                TextField(AppLocalization.string("SSH Username"), text: $draft.username)
                    .accessibilityIdentifier("ssh-username")
                    .autocorrectionDisabled()
                Picker(AppLocalization.string("SSH Authentication"), selection: $draft.authentication) {
                    Text(AppLocalization.string("Password")).tag(SSHConfiguration.Authentication.password)
                    Text(AppLocalization.string("Ed25519 Private Key")).tag(SSHConfiguration.Authentication.ed25519)
                }
                .accessibilityIdentifier("ssh-authentication")
                if draft.authentication == .password {
                    SecureField(AppLocalization.string(draft.keepSavedCredential ? "SSH Password (leave blank to keep)" : "SSH Password"), text: $draft.password)
                        .accessibilityIdentifier("ssh-password")
                } else {
                    Text(AppLocalization.string(draft.keepSavedCredential ? "Private Key (leave blank to keep)" : "OpenSSH Private Key"))
                    Button(AppLocalization.string("Import Private Key")) { importingKey = true }
                        .accessibilityIdentifier("ssh-import-key")
                    if importInProgress { ProgressView().accessibilityLabel(AppLocalization.string("Import Private Key")) }
                    if !draft.privateKey.isEmpty {
                        Text(keyFileName ?? AppLocalization.string("Private Key Selected"))
                            .foregroundStyle(.secondary)
                        Button(AppLocalization.string("Remove Selected Key")) {
                            draft.privateKey = ""; draft.passphrase = ""; keyFileName = nil
                        }
                        SecureField(AppLocalization.string("Private Key Passphrase (optional)"), text: $draft.passphrase)
                            .accessibilityIdentifier("ssh-passphrase")
                    }
                }
                TextField(AppLocalization.string("Screen Sharing Host from SSH Server"), text: $draft.destinationHost)
                    .accessibilityIdentifier("ssh-destination")
                    .autocorrectionDisabled()
            }
        }
        .disabled(importInProgress)
        .onDisappear { importGeneration = UUID() }
        .fileImporter(isPresented: $importingKey, allowedContentTypes: [.item]) { result in
            do {
                let url = try result.get()
                let generation = UUID()
                importGeneration = generation
                importInProgress = true
                Task {
                    defer { importInProgress = false }
                    do {
                        let data = try await Task.detached { try SSHConnectionDraft.readPrivateKey(from: url) }.value
                        guard importGeneration == generation else { return }
                        try draft.importPrivateKey(data)
                        keyFileName = url.lastPathComponent
                    } catch {
                        guard importGeneration == generation else { return }
                        importFailed = true
                    }
                }
            } catch {
                // Keep the previously selected key when a replacement fails.
                if (error as? CocoaError)?.code != .userCancelled { importFailed = true }
            }
        }
        .alert(AppLocalization.string("Unable to Import Private Key"), isPresented: $importFailed) {
            Button(AppLocalization.string("OK")) { importFailed = false }
        } message: {
            Text(AppLocalization.string("Choose an OpenSSH Ed25519 private key smaller than 64 KiB."))
        }
        #if canImport(UIKit)
        .textInputAutocapitalization(.never)
        #endif
    }
}
