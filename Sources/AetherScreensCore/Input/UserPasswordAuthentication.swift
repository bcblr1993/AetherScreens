import Foundation
import LocalAuthentication

private final class PasswordAuthenticationContext: @unchecked Sendable {
    let context = LAContext()
}

enum UserPasswordAuthentication {
    @MainActor
    static func authenticate() async -> Bool {
        let holder = PasswordAuthenticationContext()
        return await withTaskCancellationHandler {
            do {
                return try await holder.context.evaluatePolicy(.deviceOwnerAuthentication,
                    localizedReason: AppLocalization.string("Authenticate to type your saved user password on the remote Mac."))
            } catch { return false }
        } onCancel: {
            holder.context.invalidate()
        }
    }
}
