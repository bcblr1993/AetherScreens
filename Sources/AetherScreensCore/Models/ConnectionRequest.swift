import Foundation
import Network

/// A validated connection request. Passwords live only in memory until saving is explicitly selected.
public struct ConnectionRequest {
    public let device: RemoteDevice
    public let password: String?
    public let sshPassword: String?
    public let sshPrivateKey: Data?

    public init?(host: String, port: String = "5900", name: String = "",
                 username: String = "", password: String = "",
                 type: RemoteDevice.DeviceType = .mac, macAddress: String = "",
                 ssh: SSHConnectionSettings? = nil, sshPassword: String = "", sshPrivateKey: Data? = nil) {
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
        self.sshPassword = ssh == nil || sshPassword.isEmpty ? nil : sshPassword
        if case .privateKey = ssh?.authentication { self.sshPrivateKey = sshPrivateKey }
        else { self.sshPrivateKey = nil }
        device = RemoteDevice(name: label.isEmpty ? address : label, host: address, port: portNumber,
                              deviceType: type,
                              authMethod: account.isEmpty ? (password.isEmpty ? .none : .vncPassword) : .macAccount,
                              username: account.isEmpty ? nil : account,
                              macAddress: mac.isEmpty ? nil : mac, ssh: ssh)
    }
}
