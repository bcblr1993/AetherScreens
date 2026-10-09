import Foundation

/// Form-only state. Passwords are intentionally excluded from Codable models.
public struct SSHConnectionDraft {
    public var enabled = false
    public var serverHost = ""
    public var port = "22"
    public var username = ""
    public var remoteHost = "127.0.0.1"
    public var password = ""
    public enum AuthenticationMode: String, CaseIterable { case password, privateKey }
    public var authenticationMode: AuthenticationMode = .password
    public private(set) var keyReference: UUID?
    public private(set) var privateKeyData: Data?
    public private(set) var keyFingerprint: String?

    public mutating func importPrivateKey(_ data: Data) throws {
        let key = try SSHPrivateKey.decode(data)
        let fingerprint = try SSHPrivateKey.fingerprint(key)
        privateKeyData = data
        keyFingerprint = fingerprint
        keyReference = UUID()
        authenticationMode = .privateKey
    }
    public var privateKeyToSave: Data? { enabled && authenticationMode == .privateKey ? privateKeyData : nil }

    /// Select a validated vault identity without staging secret bytes for saving.
    public mutating func useSavedPrivateKey(reference: UUID, fingerprint: String) {
        keyReference = reference
        keyFingerprint = fingerprint
        privateKeyData = nil
        authenticationMode = .privateKey
    }

    public init(settings: SSHConnectionSettings? = nil, keyFingerprint: String? = nil) {
        guard let settings else { return }
        enabled = true
        serverHost = settings.server.host
        port = String(settings.server.port)
        username = settings.username
        remoteHost = settings.remoteHost
        if case .privateKey(let reference) = settings.authentication {
            authenticationMode = .privateKey
            keyReference = reference
            self.keyFingerprint = keyFingerprint
        }
    }

    public var settings: SSHConnectionSettings? {
        guard enabled, let number = UInt16(port.trimmingCharacters(in: .whitespacesAndNewlines)),
              let server = SSHServerAddress(host: serverHost, port: number) else { return nil }
        let authentication: SSHConnectionSettings.Authentication
        if authenticationMode == .privateKey {
            guard let keyReference else { return nil }
            authentication = .privateKey(keyReference)
        } else { authentication = .password }
        return SSHConnectionSettings(server: server, username: username,
                                     authentication: authentication, remoteHost: remoteHost)
    }
    public var isValid: Bool { !enabled || settings != nil }
    public var passwordToSave: String? { enabled && authenticationMode == .password && !password.isEmpty ? password : nil }
}
