import SwiftUI

public struct SessionSSHPrompt: Identifiable {
    public enum Kind {
        case password
        case host(SSHHostKey, SSHHostTrustStore.Assessment)
    }
    public let id = UUID()
    public let settings: SSHConnectionSettings
    public let kind: Kind
    public var error: String?
}

struct SessionSSHSheet: View {
    @ObservedObject var viewModel: SessionViewModel
    let prompt: SessionSSHPrompt
    @State private var password = ""
    @State private var remember = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(AppLocalization.string("Server"), value: "\(prompt.settings.server.host):\(prompt.settings.server.port)")
                    LabeledContent(AppLocalization.string("Username"), value: prompt.settings.username)
                }
                switch prompt.kind {
                case .password:
                    Section {
                        SecureField(AppLocalization.string("Password"), text: $password)
                            .onSubmit(submitPassword)
                            .accessibilityIdentifier("ssh-password")
                        if viewModel.canRememberPassword {
                            Toggle(AppLocalization.string("Remember in Keychain"), isOn: $remember)
                        }
                        if let error = prompt.error { Text(error).foregroundStyle(.red) }
                    }
                case .host(let key, let assessment):
                    Section {
                        if case .changed(let previous) = assessment {
                            Text(AppLocalization.string("The SSH host key has changed. Verify the new fingerprint with the server administrator before continuing."))
                                .foregroundStyle(.red)
                            fingerprint(previous.fingerprint, title: "Previous fingerprint")
                        } else {
                            Text(AppLocalization.string("Verify this fingerprint before trusting the SSH server."))
                        }
                        fingerprint(key.fingerprint, title: "SHA256 fingerprint")
                    }
                }
            }
            .navigationTitle(AppLocalization.string(title))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel")) { viewModel.cancelSSHPrompt(promptID: prompt.id) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    switch prompt.kind {
                    case .password:
                        Button(AppLocalization.string("Connect"), action: submitPassword)
                    case .host:
                        Button(AppLocalization.string("Trust and Connect")) { viewModel.approveSSHHost(promptID: prompt.id) }
                            .accessibilityIdentifier("ssh-trust-host")
                    }
                }
            }
        }
        #if os(macOS)
        .frame(width: 500, height: 420)
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
        .onDisappear { viewModel.cancelSSHPrompt(promptID: prompt.id) }
    }

    private var title: String {
        switch prompt.kind { case .password: return "SSH Authentication"; case .host: return "SSH Server Identity" }
    }
    private func submitPassword() { viewModel.submitSSHPassword(password, remember: remember, promptID: prompt.id) }
    private func fingerprint(_ value: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalization.string(title)).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
