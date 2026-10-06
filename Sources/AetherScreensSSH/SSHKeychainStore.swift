import Foundation
import Security
import LocalAuthentication
import NIOSSH

/// Durable SSH storage with no memory fallback and no automatic key replacement.
public final class SSHKeychainStore: @unchecked Sendable {
    public static let shared = SSHKeychainStore()
    public enum Failure: Error, Equatable {
        case keychain(OSStatus), invalidRecord, credentialMismatch, changedHostKey
    }
    private let backend: SSHSecretBackend
    private let lock = NSLock()
    public init(service: String = "com.aethernative.aetherscreens.ssh") {
        backend = SystemSSHSecretBackend(service: service)
    }
    init(backend: SSHSecretBackend) { self.backend = backend }

    public func save(_ credentials: SSHSessionCredentials, for deviceID: UUID,
                     configuration: SSHConfiguration) throws {
        lock.lock(); defer { lock.unlock() }
        let record: CredentialRecord
        switch credentials {
        case .password(let password):
            guard configuration.authentication == .password, !password.isEmpty else { throw Failure.credentialMismatch }
            record = CredentialRecord(configuration: configuration, secret: password, passphrase: nil)
        case .ed25519PrivateKey(let key, let passphrase):
            guard configuration.authentication == .ed25519 else { throw Failure.credentialMismatch }
            try SSHPrivateKeyCost.validate(key)
            record = CredentialRecord(configuration: configuration, secret: key, passphrase: passphrase)
        }
        try backend.write(JSONEncoder().encode(record), account: "credential:" + deviceID.uuidString)
    }

    /// A saved secret cannot follow an edited endpoint, account or key type.
    public func load(for deviceID: UUID, configuration: SSHConfiguration) throws -> SSHSessionCredentials? {
        lock.lock(); defer { lock.unlock() }
        guard let data = try backend.read(account: "credential:" + deviceID.uuidString) else { return nil }
        guard let record = try? JSONDecoder().decode(CredentialRecord.self, from: data), !record.secret.isEmpty else {
            throw Failure.invalidRecord
        }
        guard record.configuration == configuration else { throw Failure.credentialMismatch }
        return configuration.authentication == .password ? .password(record.secret)
            : .ed25519PrivateKey(record.secret, passphrase: record.passphrase)
    }

    public func deleteCredentials(for deviceID: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        try backend.delete(account: "credential:" + deviceID.uuidString)
    }

    public func trustedKey(for configuration: SSHConfiguration) throws -> SSHHostKeyIdentity? {
        lock.lock(); defer { lock.unlock() }
        return try readPin(account: pinAccount(configuration))
    }

    /// Insert-only approval. Concurrent approvals cannot overwrite an existing pin.
    public func approve(_ identity: SSHHostKeyIdentity, for configuration: SSHConfiguration) throws {
        lock.lock(); defer { lock.unlock() }
        guard let key = try? NIOSSHPublicKey(openSSHPublicKey: identity.openSSHKey),
              SSHHostKeyIdentity(key: key) == identity else { throw Failure.invalidRecord }
        let account = pinAccount(configuration)
        if let existing = try readPin(account: account) {
            guard existing == identity else { throw Failure.changedHostKey }
            return
        }
        do { try backend.insert(Data(identity.openSSHKey.utf8), account: account) }
        catch Failure.keychain(errSecDuplicateItem) {
            guard try readPin(account: account) == identity else { throw Failure.changedHostKey }
        }
    }

    /// Must be invoked by an explicit user action, never by failed verification.
    public func forgetTrustedKey(for configuration: SSHConfiguration) throws {
        lock.lock(); defer { lock.unlock() }
        try backend.delete(account: pinAccount(configuration))
    }

    /// An editor may only forget the identity the user actually reviewed.
    public func forgetTrustedKey(for configuration: SSHConfiguration, matching identity: SSHHostKeyIdentity) throws {
        lock.lock(); defer { lock.unlock() }
        let account = pinAccount(configuration)
        guard let existing = try readPin(account: account) else { return }
        guard existing == identity else { throw Failure.changedHostKey }
        try backend.delete(account: account)
    }

    private func readPin(account: String) throws -> SSHHostKeyIdentity? {
        guard let data = try backend.read(account: account) else { return nil }
        guard let text = String(data: data, encoding: .utf8),
              let key = try? NIOSSHPublicKey(openSSHPublicKey: text) else { throw Failure.invalidRecord }
        return SSHHostKeyIdentity(key: key)
    }
    private func pinAccount(_ configuration: SSHConfiguration) -> String {
        // A length-independent encoding avoids IPv6/port delimiter collisions.
        "host:" + Data(configuration.host.lowercased().utf8).base64EncodedString() + ":" + String(configuration.port)
    }
    private struct CredentialRecord: Codable {
        let configuration: SSHConfiguration
        let secret: String
        let passphrase: String?
    }
}

protocol SSHSecretBackend {
    func read(account: String) throws -> Data?
    func write(_ data: Data, account: String) throws
    func insert(_ data: Data, account: String) throws
    func delete(account: String) throws
}

private struct SystemSSHSecretBackend: SSHSecretBackend {
    let service: String
    private func query(_ account: String) -> [String: Any] {
        let context = LAContext(); context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service, kSecAttrAccount as String: account,
                kSecUseAuthenticationContext as String: context]
    }
    func read(account: String) throws -> Data? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SSHKeychainStore.Failure.keychain(status) }
        guard let data = result as? Data else { throw SSHKeychainStore.Failure.invalidRecord }
        return data
    }
    func write(_ data: Data, account: String) throws {
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            do { try insert(data, account: account) }
            catch SSHKeychainStore.Failure.keychain(errSecDuplicateItem) {
                let retry = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
                guard retry == errSecSuccess else { throw SSHKeychainStore.Failure.keychain(retry) }
            }
        } else if status != errSecSuccess { throw SSHKeychainStore.Failure.keychain(status) }
    }
    func insert(_ data: Data, account: String) throws {
        var query = query(account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw SSHKeychainStore.Failure.keychain(status) }
    }
    func delete(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SSHKeychainStore.Failure.keychain(status) }
    }
}
