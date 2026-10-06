import SwiftUI
import AetherScreensSSH

struct SSHTrustSheet: View {
    let request: SessionViewModel.SSHTrustRequest
    let canRemember: Bool
    let submit: (SSHSessionCoordinator.TrustDecision) -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(AppLocalization.string("Verify this fingerprint with the computer owner before trusting the SSH server."))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section(AppLocalization.string("SSH Server")) {
                    LabeledContent(AppLocalization.string("Address"), value: request.configuration.host)
                    LabeledContent(AppLocalization.string("Port"), value: String(request.configuration.port))
                    LabeledContent(AppLocalization.string("Username"), value: request.configuration.username)
                }
                Section(AppLocalization.string("Host Key Fingerprint")) {
                    Text(request.identity.fingerprint)
                        .accessibilityLabel(request.identity.fingerprint)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("ssh-host-fingerprint")
                }
                Section {
                    Button(AppLocalization.string("Trust Once")) { submit(.once) }
                        .frame(minHeight: 44).accessibilityIdentifier("ssh-trust-once")
                    if canRemember {
                        Button(AppLocalization.string("Trust and Remember")) { submit(.remember) }
                            .frame(minHeight: 44).accessibilityIdentifier("ssh-trust-remember")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(AppLocalization.string("Verify SSH Server"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel")) { submit(.cancel) }
                }
            }
        }
        #if os(macOS)
        .frame(width: 520, height: 510)
        #endif
    }
}
