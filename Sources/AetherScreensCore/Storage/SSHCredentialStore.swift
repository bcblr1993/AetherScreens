import Foundation
import Security

/// SSH secrets stay in Keychain. A failed write is never reported as a saved secret.
public final class SSHCredentialStore: @unchecked Sendable {
    public enum Kind: String, Sendable { case password, privateKey, passphrase }
    public struct Failure: Error, Equatable, LocalizedError {
        public let status: OSStatus
        public var errorDescription: String? { SecCopyErrorMessageString(status, nil).map { $0 as String } }
    }
    public static let shared = SSHCredentialStore()
    private let service: String
    private let access: SSHKeychainAccess
    private let lock = NSLock()

    public convenience init(service: String = "com.aethernative.aetherscreens.ssh.credentials") {
        self.init(service: service, access: SystemSSHKeychainAccess())
    }
    init(service: String, access: SSHKeychainAccess) { self.service = service; self.access = access }

    public func save(_ secret: Data, kind: Kind, reference: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        let query = query(kind: kind, reference: reference)
        let status = access.update(query, attributes: [kSecValueData as String: secret])
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw failure(status, operation: "update") }
        var attributes = query
        attributes[kSecValueData as String] = secret
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = access.add(attributes)
        guard added == errSecSuccess else { throw failure(added, operation: "add") }
    }

    public func load(kind: Kind, reference: UUID) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        var query = query(kind: kind, reference: reference)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, data) = access.copy(query)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data else { throw failure(status == errSecSuccess ? errSecDecode : status, operation: "read") }
        return data
    }

    public func remove(kind: Kind, reference: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        let status = access.delete(query(kind: kind, reference: reference))
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status, operation: "delete") }
    }

    /// Enumerate identity metadata only; no private material is requested.
    public func references(kind: Kind) throws -> [UUID] {
        lock.lock(); defer { lock.unlock() }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrSynchronizable as String: false]
        let (status, accounts) = access.accounts(query)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let accounts else {
            throw failure(status == errSecSuccess ? errSecDecode : status, operation: "list")
        }
        let prefix = kind.rawValue + "."
        var identities = Set<UUID>()
        for account in accounts where account.hasPrefix(prefix) {
            guard let reference = UUID(uuidString: String(account.dropFirst(prefix.count))) else {
                throw failure(errSecDecode, operation: "list")
            }
            identities.insert(reference)
        }
        return identities.sorted { $0.uuidString < $1.uuidString }
    }

    private func failure(_ status: OSStatus, operation: String) -> Failure {
        // Status-only diagnostics: never include account references or secrets.
        AppLogger.shared.error("SSH Keychain \(operation) failed (status \(status)).", category: "Auth")
        return Failure(status: status)
    }

    private func query(kind: Kind, reference: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: kind.rawValue + "." + reference.uuidString,
         kSecAttrSynchronizable as String: false]
    }
}

protocol SSHKeychainAccess {
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func add(_ attributes: [String: Any]) -> OSStatus
    func copy(_ query: [String: Any]) -> (OSStatus, Data?)
    func delete(_ query: [String: Any]) -> OSStatus
    func accounts(_ query: [String: Any]) -> (OSStatus, [String]?)
}

extension SSHKeychainAccess {
    func accounts(_ query: [String: Any]) -> (OSStatus, [String]?) { (errSecUnimplemented, nil) }
}

private struct SystemSSHKeychainAccess: SSHKeychainAccess {
    func accounts(_ query: [String: Any]) -> (OSStatus, [String]?) {
        var query = query
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return (status, nil) }
        guard let rows = result as? [[String: Any]] else { return (errSecDecode, nil) }
        var accounts: [String] = []
        for row in rows {
            guard let account = row[kSecAttrAccount as String] as? String else { return (errSecDecode, nil) }
            accounts.append(account)
        }
        return (status, accounts)
    }
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }
    func add(_ attributes: [String: Any]) -> OSStatus { SecItemAdd(attributes as CFDictionary, nil) }
    func copy(_ query: [String: Any]) -> (OSStatus, Data?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }
    func delete(_ query: [String: Any]) -> OSStatus { SecItemDelete(query as CFDictionary) }
}
