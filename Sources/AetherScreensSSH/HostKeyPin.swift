import Citadel
import NIOSSH

/// Callers must provide the trusted server key explicitly.
/// No trust-all fallback is available through this interface.
public enum HostKeyPin {
    public static func validator(for key: NIOSSHPublicKey) -> SSHHostKeyValidator {
        .trustedKeys([key])
    }
}
