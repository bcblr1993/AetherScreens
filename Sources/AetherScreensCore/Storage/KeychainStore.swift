import Foundation
import Security

protocol DevicePasswordStore: Sendable {
    @discardableResult func savePassword(_ password: String, forKey key: String) -> Bool
    func loadPassword(forKey key: String) -> String?
    @discardableResult func deletePassword(forKey key: String) -> Bool
}

extension KeychainStore: DevicePasswordStore {}

/// Injectable primitives keep credential behavior testable without opening the
/// user's Keychain. The store owns serialization and its existing memory cache.
protocol KeychainSecretBackend: Sendable {
    func read(service: String, key: String) -> Data?
    func write(_ data: Data, service: String, key: String) -> Bool
    func delete(service: String, key: String) -> OSStatus
}

/// Secure storage helper using system Keychain for passwords, with memory cache fallback.
public final class KeychainStore: @unchecked Sendable {
    public static let shared = KeychainStore()

    public static let defaultServiceName = "com.aethernative.aetherscreens.credentials"
    /// Service used by builds released under the TailScreens name. Items are moved to the current service on first read.
    public static let legacyServiceName = "com.tailscreens.credentials"

    private let serviceName: String
    private let legacyServiceName: String?
    private let backend: any KeychainSecretBackend
    private var inMemoryStore: [String: String] = [:]
    private let lock = NSLock()

    public init(serviceName: String = KeychainStore.defaultServiceName,
                legacyServiceName: String? = KeychainStore.legacyServiceName) {
        self.serviceName = serviceName
        self.legacyServiceName = legacyServiceName
        self.backend = SystemKeychainSecretBackend()
    }

    init(serviceName: String = KeychainStore.defaultServiceName,
         legacyServiceName: String? = KeychainStore.legacyServiceName,
         backend: any KeychainSecretBackend) {
        self.serviceName = serviceName
        self.legacyServiceName = legacyServiceName
        self.backend = backend
    }

    /// Save a password for a given device ID or key.
    @discardableResult
    public func savePassword(_ password: String, forKey key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        inMemoryStore[key] = password

        guard let data = password.data(using: .utf8) else { return false }
        return writeItem(data, service: serviceName, key: key)
    }

    /// Retrieve a saved password for a given device ID or key.
    public func loadPassword(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }

        if let cached = inMemoryStore[key] {
            return cached
        }

        if let data = readItem(service: serviceName, key: key),
           let password = String(data: data, encoding: .utf8) {
            inMemoryStore[key] = password
            return password
        }

        // Migrate a password saved by a TailScreens build, then drop the legacy copy.
        if let legacyServiceName,
           let data = readItem(service: legacyServiceName, key: key),
           let password = String(data: data, encoding: .utf8) {
            if writeItem(data, service: serviceName, key: key) {
                deleteItem(service: legacyServiceName, key: key)
                AppLogger.shared.info("Migrated legacy Keychain password for \(key)", category: "Auth")
            }
            inMemoryStore[key] = password
            return password
        }

        return nil
    }

    /// Delete a saved password.
    @discardableResult
    public func deletePassword(forKey key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        inMemoryStore.removeValue(forKey: key)

        if let legacyServiceName {
            deleteItem(service: legacyServiceName, key: key)
        }
        let status = deleteItem(service: serviceName, key: key)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Keychain primitives (callers hold `lock`)

    private func readItem(service: String, key: String) -> Data? {
        backend.read(service: service, key: key)
    }

    private func writeItem(_ data: Data, service: String, key: String) -> Bool {
        backend.write(data, service: service, key: key)
    }

    @discardableResult
    private func deleteItem(service: String, key: String) -> OSStatus {
        backend.delete(service: service, key: key)
    }
}

private struct SystemKeychainSecretBackend: KeychainSecretBackend {
    func read(service: String, key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    func write(_ data: Data, service: String, key: String) -> Bool {
        // Remove existing item if present
        _ = delete(service: service, key: key)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    func delete(service: String, key: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        return SecItemDelete(query as CFDictionary)
    }
}
