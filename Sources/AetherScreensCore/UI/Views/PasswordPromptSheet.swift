import SwiftUI

/// Elegant authentication modal prompting user for VNC credentials when connecting to a remote Mac.
public struct PasswordPromptSheet: View {
    public let deviceName: String
    public let host: String
    public let username: String?
    public let errorMessage: String?
    public let canRememberPassword: Bool
    public let onSubmit: (String, Bool) -> Void
    public let onCancel: () -> Void

    @State private var password: String = ""
    @State private var saveToKeychain: Bool = true
    @FocusState private var isPasswordFocused: Bool

    public init(
        deviceName: String,
        host: String,
        username: String? = nil,
        errorMessage: String? = nil,
        canRememberPassword: Bool = true,
        onSubmit: @escaping (String, Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.deviceName = deviceName
        self.host = host
        self.username = username
        self.errorMessage = errorMessage
        self.canRememberPassword = canRememberPassword
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 56, height: 56)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 26))
                        .foregroundColor(.accentColor)
                }

                Text("Authentication Required")
                    .font(.system(size: 18, weight: .bold))

                Text(username == nil ? "Enter the VNC password for \(deviceName)" : "Enter the Mac account password for \(username!)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Text(host)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 8)

            if let err = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Input Fields
            VStack(alignment: .leading, spacing: 12) {
                SecureField(username == nil ? "VNC Password" : "Mac Account Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14))
                    .focused($isPasswordFocused)
                    .onSubmit {
                        if !password.isEmpty {
                            onSubmit(password, canRememberPassword && saveToKeychain)
                        }
                    }

                if canRememberPassword {
                    Toggle("Save password in Keychain", isOn: $saveToKeychain)
                    .font(.system(size: 13))
                    #if os(macOS)
                    .toggleStyle(.checkbox)
                    #endif
                }
            }
            .padding(.horizontal, 8)

            // Action Buttons
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Connect") {
                    onSubmit(password, canRememberPassword && saveToKeychain)
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(maxWidth: 420)
        #if os(macOS)
        .frame(minWidth: 360)
        #endif
        .onAppear {
            isPasswordFocused = true
        }
    }
}
