import SwiftUI

/// A per-import identity prevents a dismissed derivation from applying to a later import.
struct EncryptedSSHKeyImport: Identifiable {
    let id = UUID()
    let data: Data

    static func request(for data: Data) throws -> Self? {
        guard data.count <= SSHPrivateKey.maximumSize else { throw SSHPrivateKey.Failure.tooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw SSHPrivateKey.Failure.invalid }
        return text.contains("-----BEGIN ENCRYPTED PRIVATE KEY-----") ? Self(data: data) : nil
    }
}

struct SSHKeyUnlockSheet: View {
    let request: EncryptedSSHKeyImport
    let imported: (Data) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var passphrase = ""
    @State private var errorMessage: String?
    @State private var task: Task<Void, Never>?
    @State private var busy = false
    @State private var active = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(AppLocalization.string("Private Key Passphrase"), text: $passphrase)
                        .accessibilityIdentifier("ssh-key-passphrase")
                        .disabled(busy)
                        .onSubmit { unlock() }
                    Text(AppLocalization.string("The passphrase is used only to unlock this import. The unlocked key stays in Keychain or this session."))
                        .font(.caption).foregroundStyle(.secondary)
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                    if busy { ProgressView(AppLocalization.string("Unlocking Private Key")) }
                }
            }
            .navigationTitle(AppLocalization.string("Unlock Private Key"))
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel")) { cancel(); dismiss() }
                        .accessibilityIdentifier("ssh-key-unlock-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("Unlock")) { unlock() }
                        .disabled(busy).accessibilityIdentifier("ssh-key-unlock")
                }
            }
        }
        #if os(macOS)
        .frame(width: 480, height: 280)
        #endif
        .onDisappear { cancel() }
    }

    private func cancel() {
        active = false
        task?.cancel()
        task = nil
        passphrase = ""
    }

    private func unlock() {
        guard !busy, active else { return }
        busy = true
        errorMessage = nil
        let data = request.data
        let phrase = passphrase
        task = Task { @MainActor in
            do {
                // CommonCrypto's bounded derivation is synchronous; keep it off the UI executor.
                let worker = Task.detached(priority: .userInitiated) {
                    try Task.checkCancellation()
                    let normalized = try EncryptedPKCS8PrivateKey.decrypt(data, passphrase: phrase)
                    try Task.checkCancellation()
                    return normalized
                }
                let normalized = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                guard active else { return }
                try imported(normalized)
                passphrase = ""
                dismiss()
            } catch {
                guard active, !Task.isCancelled else { return }
                if let failure = error as? EncryptedPKCS8PrivateKey.Failure,
                   failure == .unsupported || failure == .tooExpensive {
                    errorMessage = AppLocalization.string("This encrypted key uses an unsupported encryption profile. Use PBKDF2 and AES-CBC with an ECDSA PKCS#8 key.")
                } else {
                    errorMessage = AppLocalization.string("Could not unlock the private key. Check the passphrase and key file.")
                }
                passphrase = ""
                busy = false
                task = nil
            }
        }
    }
}
