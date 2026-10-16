import SwiftUI

/// Elegant privacy and biometric security overlay presented when the application is locked.
@MainActor
public struct AppLockOverlayView: View {
    @ObservedObject var service: AppLockService
    @State private var isAuthenticating = false

    public init(service: AppLockService) {
        self.service = service
    }

    public init() {
        self.service = .shared
    }

    public var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 88, height: 88)

                    Image(systemName: service.biometryType.systemIconName)
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(Color.blue)
                }

                VStack(spacing: 8) {
                    Text(AppLocalization.string("AetherScreens is Locked"))
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    Text(AppLocalization.string("Authenticate to access your remote computers and saved credentials."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }

                Button {
                    authenticate()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: service.biometryType.systemIconName)
                        Text(AppLocalization.string("Unlock"))
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isAuthenticating)
                .accessibilityIdentifier("app-lock-unlock-button")
            }
            .padding(32)
        }
        .accessibilityIdentifier("app-lock-overlay")
        .task {
            // Auto prompt for authentication on presentation
            authenticate()
        }
    }

    private func authenticate() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        Task { @MainActor in
            _ = await service.unlock()
            isAuthenticating = false
        }
    }
}
