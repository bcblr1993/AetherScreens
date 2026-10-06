import Foundation
import Network
import AetherScreensSSH

/// A validated connection request. Passwords live only in memory until saving is explicitly selected.
public struct ConnectionRequest {
    public let device: RemoteDevice
    public let password: String?
    public let sshCredentials: SSHSessionCredentials?

    public init?(host: String, port: String = "5900", name: String = "",
                 username: String = "", password: String = "",
                 type: RemoteDevice.DeviceType = .mac, macAddress: String = "",
                 sshConfiguration: SSHConfiguration? = nil, sshCredentials: SSHSessionCredentials? = nil) {
        var address = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if address.hasPrefix("[") && address.hasSuffix("]") {
            address = String(address.dropFirst().dropLast())
        }
        guard !address.isEmpty, !address.contains(where: { $0.isWhitespace }),
              !address.contains("/"), !address.contains("@"), !address.contains("["), !address.contains("]"),
              !address.contains(":") || IPv6Address(address) != nil,
              let portNumber = UInt16(port.trimmingCharacters(in: .whitespacesAndNewlines)), portNumber > 0 else { return nil }
        let account = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let mac = macAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        self.password = password.isEmpty ? nil : password
        if let configuration = sshConfiguration {
            switch (configuration.authentication, sshCredentials) {
            case (.password, .password(let secret)) where !secret.isEmpty: break
            case (.ed25519, .ed25519PrivateKey(let key, _)) where !key.isEmpty: break
            default: return nil
            }
        } else if sshCredentials != nil { return nil }
        self.sshCredentials = sshCredentials
        var target = RemoteDevice(name: label.isEmpty ? address : label, host: address, port: portNumber,
                              deviceType: type,
                              authMethod: account.isEmpty ? (password.isEmpty ? .none : .vncPassword) : .macAccount,
                              username: account.isEmpty ? nil : account,
                              macAddress: mac.isEmpty ? nil : mac)
        target.sshConfiguration = sshConfiguration
        device = target
    }
}
