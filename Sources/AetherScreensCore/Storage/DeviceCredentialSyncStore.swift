import Foundation
import Security
import LocalAuthentication
import CryptoKit
import AetherScreensSSH

/// Secrets use the system keychain, never the device document or preferences.
/// Construction alone does not query iCloud. The library controller enables cloud
/// access only after its metadata exchange verifies the bound account.
public final class DeviceCredentialSyncStore: @unchecked Sendable {
    public enum Failure: Error, Equatable, Sendable {
        case notConfigured, keychain(OSStatus), invalidRecord, credentialMismatch, conflict, cloudDisabled
    }
    enum Kind: String, Codable, CaseIterable { case password, ssh }
    enum Read<Value> { case missing, deleted, value(Value) }
    private struct Binding: Codable, Equatable {
        let id: UUID
        let host: String
        let port: UInt16
        let authentication: RemoteDevice.AuthMethod
        let username: String?
        let ssh: SSHConfiguration?
        init(_ device: RemoteDevice) {
            id = device.id; host = device.host; port = device.port
            authentication = device.authMethod; username = device.username; ssh = device.sshConfiguration
        }
    }
    private struct Record: Codable {
        let version: Int
        let id: UUID
        let kind: Kind
        let revision: UUID
        let binding: Binding?
        let secret: String?
        let passphrase: String?
        var deleted: Bool { binding == nil }
        init(device: RemoteDevice, kind: Kind, secret: String, passphrase: String? = nil) {
            version = 1; id = device.id; self.kind = kind; revision = UUID()
            binding = Binding(device); self.secret = secret; self.passphrase = passphrase
        }
        init(deleting id: UUID, kind: Kind) {
            version = 1; self.id = id; self.kind = kind; revision = UUID()
            binding = nil; secret = nil; passphrase = nil
        }
    }
    private struct Pending: Codable {
        let version: Int
        let record: Data
        let parentDigest: String?
    }
    private let backend: any DeviceCredentialBackend
    private let defaults: UserDefaults
    private let indexKey: String
    private let lock = NSLock()
    private var cloudAccess = false
    private static let maximumRecordBytes = 128 * 1024

    /// Both identifiers must come from the provisioned app configuration; the
    /// account is the identifier verified by DeviceSyncExchange, not a login name.
    public convenience init(containerIdentifier: String, verifiedAccount: String,
                            accessGroup: String, defaults: UserDefaults = .standard) throws {
        guard containerIdentifier.hasPrefix("iCloud."), !verifiedAccount.isEmpty,
              verifiedAccount.utf8.count <= 1024, !accessGroup.isEmpty,
              !accessGroup.contains("*"), accessGroup.utf8.count <= 255 else { throw Failure.notConfigured }
        let namespace = Self.namespace(container: containerIdentifier, account: verifiedAccount)
        self.init(backend: SystemDeviceCredentialBackend(
            service: "com.aethernative.aetherscreens.synced-credentials." + namespace,
            accessGroup: accessGroup), defaults: defaults, namespace: namespace)
    }

    init(backend: any DeviceCredentialBackend, defaults: UserDefaults, namespace: String) {
        self.backend = backend; self.defaults = defaults
        indexKey = "com.aethernative.aetherscreens.credentials.pending." + namespace
    }

    static func namespace(container: String, account: String) -> String {
        // Length-prefixing prevents delimiter collisions without storing either identifier.
        digest(Data((String(container.utf8.count) + ":" + container + account).utf8))!
    }

    func setCloudAccess(_ enabled: Bool) {
        lock.lock(); defer { lock.unlock() }; cloudAccess = enabled
    }

    func stagePassword(_ password: String, for device: RemoteDevice) throws {
        guard device.authMethod != .none, !password.isEmpty, password.utf8.count <= 65_536 else {
            throw Failure.credentialMismatch
        }
        try stage(Record(device: device, kind: .password, secret: password))
    }

    func stageSSH(_ credentials: SSHSessionCredentials, for device: RemoteDevice) throws {
        guard let configuration = device.sshConfiguration else { throw Failure.credentialMismatch }
        let record: Record
        switch credentials {
        case .password(let password):
            guard configuration.authentication == .password else { throw Failure.credentialMismatch }
            record = Record(device: device, kind: .ssh, secret: password)
        case .ed25519PrivateKey(let key, let passphrase):
            guard configuration.authentication == .ed25519 else { throw Failure.credentialMismatch }
            record = Record(device: device, kind: .ssh, secret: key, passphrase: passphrase)
        }
        try stage(record)
    }

    func stageDeletion(for id: UUID, sshOnly: Bool = false) throws {
        for kind in sshOnly ? [Kind.ssh] : Kind.allCases { try stage(Record(deleting: id, kind: kind)) }
    }

    func stagePasswordDeletion(for id: UUID) throws { try stage(Record(deleting: id, kind: .password)) }

    func password(for device: RemoteDevice) throws -> Read<String> {
        lock.lock(); defer { lock.unlock() }
        guard let record = try load(id: device.id, kind: .password) else { return .missing }
        if record.deleted { return .deleted }
        guard record.binding == Binding(device) else { throw Failure.credentialMismatch }
        return .value(record.secret!)
    }

    func sshCredentials(for device: RemoteDevice) throws -> Read<SSHSessionCredentials> {
        lock.lock(); defer { lock.unlock() }
        guard let record = try load(id: device.id, kind: .ssh) else { return .missing }
        if record.deleted { return .deleted }
        guard record.binding == Binding(device), let configuration = device.sshConfiguration else {
            throw Failure.credentialMismatch
        }
        return .value(configuration.authentication == .password ? .password(record.secret!)
            : .ed25519PrivateKey(record.secret!, passphrase: record.passphrase))
    }

    /// Called after metadata import/publication and account verification. Pending
    /// writes survive a process restart; stale endpoints never relabel a secret.
    func synchronize(devices: [RemoteDevice], deletedIDs: Set<UUID>,
                     localPassword: (RemoteDevice) -> String?,
                     localSSH: (RemoteDevice) throws -> SSHSessionCredentials?) throws {
        lock.lock(); defer { lock.unlock() }
        guard cloudAccess else { throw Failure.cloudDisabled }
        let live = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })
        // Metadata deletion is permanent. Empty keychain tombstones prevent an
        // older cached password from being bootstrapped back into the cloud.
        for id in deletedIDs {
            for kind in Kind.allCases {
                let account = Self.account(id, kind)
                let current = try backend.read(account: account, cloud: true)
                if let current, try decode(current, id: id, kind: kind).deleted {
                    try finish(account: account, cloudData: current)
                } else {
                    let tombstone = try encode(Record(deleting: id, kind: kind))
                    try backend.write(tombstone, account: account, cloud: true)
                    try finish(account: account, cloudData: tombstone)
                }
            }
        }
        for account in try pendingAccounts() {
            guard let data = try backend.read(account: "pending:" + account, cloud: false) else {
                removeIndex(account); continue // interrupted before staging, no secret was committed
            }
            let pending = try decodePending(data)
            let record = try decode(pending.record, account: account)
            if deletedIDs.contains(record.id) { continue }
            if !record.deleted {
                guard let device = live[record.id], record.binding == Binding(device) else {
                    throw Failure.credentialMismatch
                }
            } else if live[record.id] == nil {
                // A queued delete with no metadata tombstone is not authorized by this replica.
                throw Failure.credentialMismatch
            }
            let current = try backend.read(account: account, cloud: true)
            if let current { _ = try decode(current, account: account) }
            if current != pending.record {
                guard Self.digest(current) == pending.parentDigest else { throw Failure.conflict }
                try backend.write(pending.record, account: account, cloud: true)
            }
            try finish(account: account, cloudData: pending.record)
        }
        // Migration is insert-only. Existing cloud records (including deletions)
        // take precedence over legacy UUID-only entries on this installation.
        for device in devices {
            for kind in Kind.allCases {
                let account = Self.account(device.id, kind)
                if let data = try backend.read(account: account, cloud: true) {
                    _ = try decode(data, id: device.id, kind: kind)
                    try backend.write(data, account: "cache:" + account, cloud: false)
                    continue
                }
                let record: Record?
                switch kind {
                case .password:
                    record = device.authMethod == .none ? nil : localPassword(device).map {
                        Record(device: device, kind: kind, secret: $0)
                    }
                case .ssh:
                    switch try localSSH(device) {
                    case .password(let secret): record = Record(device: device, kind: kind, secret: secret)
                    case .ed25519PrivateKey(let key, let passphrase):
                        record = Record(device: device, kind: kind, secret: key, passphrase: passphrase)
                    case nil: record = nil
                    }
                }
                guard let record else { continue }
                let data = try encode(record)
                do { try backend.insert(data, account: account, cloud: true) }
                catch Failure.keychain(errSecDuplicateItem) { /* an unseen cloud insert wins */ }
                guard let stored = try backend.read(account: account, cloud: true) else { throw Failure.invalidRecord }
                _ = try decode(stored, id: device.id, kind: kind)
                try backend.write(stored, account: "cache:" + account, cloud: false)
            }
        }
    }

    private func stage(_ record: Record) throws {
        lock.lock(); defer { lock.unlock() }
        let account = Self.account(record.id, record.kind)
        let bytes = try encode(record)
        // A new explicit save may resolve an earlier conflict. Offline retries
        // keep their original parent; they never silently rebase themselves.
        let cached = try backend.read(account: cloudAccess ? account : "cache:" + account, cloud: cloudAccess)
        if let cached { _ = try decode(cached, account: account) }
        let pending = try JSONEncoder().encode(Pending(version: 1, record: bytes, parentDigest: Self.digest(cached)))
        var index = try pendingAccounts(); index.insert(account)
        guard index.count <= 2048 else { throw Failure.invalidRecord }
        // An index can exist without a staged value; a staged value must always
        // be discoverable. Only UUID/kind identifiers enter UserDefaults.
        defaults.set(index.sorted(), forKey: indexKey)
        try backend.write(pending, account: "pending:" + account, cloud: false)
    }

    private func load(id: UUID, kind: Kind) throws -> Record? {
        let account = Self.account(id, kind)
        if let pending = try backend.read(account: "pending:" + account, cloud: false) {
            return try decode(decodePending(pending).record, id: id, kind: kind)
        }
        if cloudAccess {
            let data = try backend.read(account: account, cloud: true)
            if let data {
                let result = try decode(data, id: id, kind: kind)
                try backend.write(data, account: "cache:" + account, cloud: false)
                return result
            }
            // Do not revive a cached secret if the authoritative item disappeared.
            return nil
        }
        return try backend.read(account: "cache:" + account, cloud: false).map { try decode($0, id: id, kind: kind) }
    }

    private func finish(account: String, cloudData: Data) throws {
        try backend.write(cloudData, account: "cache:" + account, cloud: false)
        try backend.delete(account: "pending:" + account, cloud: false)
        removeIndex(account)
    }

    private func removeIndex(_ account: String) {
        var index = Set(defaults.stringArray(forKey: indexKey) ?? [])
        index.remove(account); defaults.set(index.sorted(), forKey: indexKey)
    }

    private func pendingAccounts() throws -> Set<String> {
        guard let raw = defaults.object(forKey: indexKey) else { return [] }
        guard let values = raw as? [String], values.count <= 2048,
              values.allSatisfy({ value in
                  let parts = value.split(separator: ":")
                  return parts.count == 2 && Kind(rawValue: String(parts[0])) != nil && UUID(uuidString: String(parts[1])) != nil
              }) else { throw Failure.invalidRecord }
        return Set(values)
    }

    private func encode(_ record: Record) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        _ = try decode(data, id: record.id, kind: record.kind)
        return data
    }

    private func decode(_ data: Data, account: String) throws -> Record {
        let parts = account.split(separator: ":")
        guard parts.count == 2, let kind = Kind(rawValue: String(parts[0])),
              let id = UUID(uuidString: String(parts[1])) else { throw Failure.invalidRecord }
        return try decode(data, id: id, kind: kind)
    }

    private func decode(_ data: Data, id: UUID, kind: Kind) throws -> Record {
        guard data.count <= Self.maximumRecordBytes,
              let record = try? JSONDecoder().decode(Record.self, from: data),
              record.version == 1, record.id == id, record.kind == kind else { throw Failure.invalidRecord }
        if record.deleted {
            guard record.secret == nil, record.passphrase == nil else { throw Failure.invalidRecord }
        } else {
            guard record.binding?.id == id, let secret = record.secret, !secret.isEmpty,
                  secret.utf8.count <= 65_536, (record.passphrase?.utf8.count ?? 0) <= 4096 else {
                throw Failure.invalidRecord
            }
            if kind == .password {
                guard record.binding?.authentication != RemoteDevice.AuthMethod.none, record.passphrase == nil else { throw Failure.invalidRecord }
            } else {
                guard let configuration = record.binding?.ssh else { throw Failure.invalidRecord }
                if configuration.authentication == .ed25519 {
                    do { try SSHPrivateKeyCost.validate(secret) } catch { throw Failure.invalidRecord }
                } else if record.passphrase != nil { throw Failure.invalidRecord }
            }
        }
        return record
    }

    private func decodePending(_ data: Data) throws -> Pending {
        guard data.count <= Self.maximumRecordBytes * 2,
              let pending = try? JSONDecoder().decode(Pending.self, from: data), pending.version == 1,
              pending.parentDigest.map({ $0.count == 64 && $0.allSatisfy(\.isHexDigit) }) ?? true else {
            throw Failure.invalidRecord
        }
        return pending
    }

    private static func account(_ id: UUID, _ kind: Kind) -> String { kind.rawValue + ":" + id.uuidString }
    private static func digest(_ bytes: Data?) -> String? {
        bytes.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
    }
}

protocol DeviceCredentialBackend: Sendable {
    func read(account: String, cloud: Bool) throws -> Data?
    func write(_ data: Data, account: String, cloud: Bool) throws
    func insert(_ data: Data, account: String, cloud: Bool) throws
    func delete(account: String, cloud: Bool) throws
}

/// Injectable Security calls keep headless tests out of the real user keychain.
protocol DeviceCredentialSecurityAPI: Sendable {
    func copy(_ query: [String: Any]) -> (OSStatus, Data?)
    func update(_ query: [String: Any], data: Data) -> OSStatus
    func add(_ query: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

struct SystemDeviceCredentialBackend: DeviceCredentialBackend {
    let service: String
    let accessGroup: String
    var api: any DeviceCredentialSecurityAPI = SystemDeviceCredentialSecurityAPI()
    func query(_ account: String, cloud: Bool) -> [String: Any] {
        let context = LAContext(); context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service, kSecAttrAccount as String: account,
                kSecAttrAccessGroup as String: accessGroup, kSecAttrSynchronizable as String: cloud,
                kSecUseDataProtectionKeychain as String: true,
                kSecUseAuthenticationContext as String: context]
    }
    func read(account: String, cloud: Bool) throws -> Data? {
        var query = query(account, cloud: cloud)
        query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, data) = api.copy(query)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw DeviceCredentialSyncStore.Failure.keychain(status) }
        guard let data else { throw DeviceCredentialSyncStore.Failure.invalidRecord }; return data
    }
    func write(_ data: Data, account: String, cloud: Bool) throws {
        let status = api.update(query(account, cloud: cloud), data: data)
        if status == errSecItemNotFound {
            do { try insert(data, account: account, cloud: cloud) }
            catch DeviceCredentialSyncStore.Failure.keychain(errSecDuplicateItem) {
                let retry = api.update(query(account, cloud: cloud), data: data)
                guard retry == errSecSuccess else { throw DeviceCredentialSyncStore.Failure.keychain(retry) }
            }
        } else if status != errSecSuccess { throw DeviceCredentialSyncStore.Failure.keychain(status) }
    }
    func insert(_ data: Data, account: String, cloud: Bool) throws {
        var query = query(account, cloud: cloud)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = cloud ? kSecAttrAccessibleAfterFirstUnlock : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = api.add(query)
        guard status == errSecSuccess else { throw DeviceCredentialSyncStore.Failure.keychain(status) }
    }
    func delete(account: String, cloud: Bool) throws {
        let status = api.delete(query(account, cloud: cloud))
        guard status == errSecSuccess || status == errSecItemNotFound else { throw DeviceCredentialSyncStore.Failure.keychain(status) }
    }
}

private struct SystemDeviceCredentialSecurityAPI: DeviceCredentialSecurityAPI {
    func copy(_ query: [String: Any]) -> (OSStatus, Data?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }
    func update(_ query: [String: Any], data: Data) -> OSStatus {
        SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    }
    func add(_ query: [String: Any]) -> OSStatus { SecItemAdd(query as CFDictionary, nil) }
    func delete(_ query: [String: Any]) -> OSStatus { SecItemDelete(query as CFDictionary) }
}
