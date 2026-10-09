import Foundation
import Darwin
import CryptoKit

/// Stable provider account identity, never the user's email or display name.
struct ComputerSyncAccountScope: Equatable {
    let digest: String
    init(accountIdentifier: String) throws {
        guard !accountIdentifier.isEmpty, accountIdentifier.utf8.count <= 4096 else {
            throw ComputerSyncCheckpoint.Failure.invalid
        }
        digest = SHA256.hash(data: Data(accountIdentifier.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Canonical local password binding contains endpoint identity, never a secret.
struct ComputerCredentialTarget: Codable {
    let host: String
    let port: UInt16
    let authMethod: RemoteDevice.AuthMethod
    let username: String?
    let ssh: SSHConnectionSettings?

    static func validateToken(_ token: String) throws {
        if token == "unbound" { return }
        guard let data = Data(base64Encoded: token) else { throw ComputerSyncCheckpoint.Failure.invalid }
        let target = try JSONDecoder().decode(Self.self, from: data)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Reject ignored/unknown keys and alternate encodings as well as broken
        // data. Do not carry arbitrary caller-provided JSON into the checkpoint.
        guard try encoder.encode(target) == data,
              target.host.utf8.count <= 1024, (target.username?.utf8.count ?? 0) <= 1024,
              ConnectionRequest(host: target.host, port: String(target.port)) != nil else {
            throw ComputerSyncCheckpoint.Failure.invalid
        }
    }
}

/// Local-only commit envelope. Never upload this file: runtime state and local
/// credential target bindings belong to this installation.
struct ComputerSyncCheckpoint: Codable, Equatable {
    let schema: Int
    let journal: Data
    let devices: [RemoteDevice]
    let credentialBindings: [String: String]
    var accountScopeDigest: String?

    init(journal: ComputerSyncJournal, devices: [RemoteDevice], credentialBindings: [String: String]) throws {
        schema = 1
        self.journal = try journal.encoded()
        self.devices = devices
        self.credentialBindings = credentialBindings
        accountScopeDigest = nil
        try validate()
    }

    func validate() throws {
        guard schema == 1, credentialBindings.count <= 2000 else { throw Failure.invalid }
        if let accountScopeDigest {
            guard accountScopeDigest.utf8.count == 64,
                  accountScopeDigest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw Failure.invalid
            }
        }
        let restored = try ComputerSyncJournal(restoring: journal)
        var validator = ComputerSyncJournal()
        try validator.captureLocalComputers(devices)
        let computers = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, ComputerSyncMetadata(device: $0)) })
        for record in restored.records.values {
            guard computers[record.id] == record.metadata else { throw Failure.invalid }
        }
        for (key, token) in credentialBindings {
            let parts = key.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, ["ssh", "vnc"].contains(String(parts[0])),
                  UUID(uuidString: String(parts[1])) != nil,
                  !token.isEmpty, token.utf8.count <= 16_384 else { throw Failure.invalid }
            try ComputerCredentialTarget.validateToken(token)
        }
    }
    enum Failure: Error { case invalid, oversized }
}

/// Writes a single validated snapshot. Before rename, failures preserve the old
/// checkpoint; after rename, a directory-sync failure explicitly reports an
/// uncertain durable commit so callers must reload rather than roll back blindly.
struct ComputerSyncCheckpointFile {
    let url: URL
    let accountScope: ComputerSyncAccountScope?
    init(url: URL, accountScope: ComputerSyncAccountScope? = nil) {
        self.url = url; self.accountScope = accountScope
    }
    enum Failure: Error { case io(Int32), durabilityUncertain(Int32), accountMismatch, busy, conflict }
    static let maximumBytes = 8 * 1024 * 1024

    // Never unlink a lock file: replacing its inode could let a second writer
    // acquire a different lock while the first writer still owns the old one.
    var lockURL: URL {
        let name = SHA256.hash(data: Data(url.lastPathComponent.utf8)).map { String(format: "%02x", $0) }.joined()
        return url.deletingLastPathComponent().appendingPathComponent(".sync-lock-" + name)
    }

    func load() throws -> ComputerSyncCheckpoint? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while data.count <= Self.maximumBytes {
            let chunk = try handle.read(upToCount: min(65_536, Self.maximumBytes + 1 - data.count)) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        guard data.count <= Self.maximumBytes else { throw ComputerSyncCheckpoint.Failure.oversized }
        let checkpoint = try JSONDecoder().decode(ComputerSyncCheckpoint.self, from: data)
        try checkpoint.validate()
        guard checkpoint.accountScopeDigest == accountScope?.digest else { throw Failure.accountMismatch }
        return checkpoint
    }

    func save(_ checkpoint: ComputerSyncCheckpoint) throws {
        try save(checkpoint, replacing: load())
    }

    /// Compare the complete prior commit while holding the writer lock. Comparing
    /// only the sync clock would miss local runtime or credential-binding changes.
    func save(_ checkpoint: ComputerSyncCheckpoint, replacing expected: ComputerSyncCheckpoint?) throws {
        try checkpoint.validate()
        guard checkpoint.accountScopeDigest == nil || checkpoint.accountScopeDigest == accountScope?.digest else {
            throw Failure.accountMismatch
        }
        let lockFD = Darwin.open(lockURL.path, O_RDWR | O_CREAT | O_NOFOLLOW, mode_t(0o600))
        guard lockFD >= 0 else { throw Failure.io(errno) }
        defer { Darwin.close(lockFD) }
        guard checkpointFlock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            if errno == EWOULDBLOCK || errno == EAGAIN { throw Failure.busy }
            throw Failure.io(errno)
        }
        defer { _ = checkpointFlock(lockFD, LOCK_UN) }
        // Refuse to replace another account's file, including an unscoped legacy
        // file. Migration needs a deliberate coordinator operation.
        guard try load() == expected else { throw Failure.conflict }
        var scoped = checkpoint
        scoped.accountScopeDigest = accountScope?.digest
        let data = try JSONEncoder().encode(scoped)
        guard data.count <= Self.maximumBytes else { throw ComputerSyncCheckpoint.Failure.oversized }
        let directory = url.deletingLastPathComponent()
        // Directory creation is a caller-owned setup operation.
        let temporary = directory.appendingPathComponent(".sync-commit-\(UUID().uuidString)")
        let fd = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw Failure.io(errno) }
        defer { Darwin.close(fd); try? FileManager.default.removeItem(at: temporary) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw Failure.io(count < 0 ? errno : EIO) }
                offset += count
            }
        }
        guard Darwin.fsync(fd) == 0 else { throw Failure.io(errno) }
        let parent = Darwin.open(directory.path, O_RDONLY | O_NOFOLLOW)
        guard parent >= 0 else { throw Failure.io(errno) }
        defer { Darwin.close(parent) }
        guard Darwin.rename(temporary.path, url.path) == 0 else { throw Failure.io(errno) }
        guard Darwin.fsync(parent) == 0 else { throw Failure.durabilityUncertain(errno) }
    }
}

// Darwin exports both a struct and a function named flock. A contextual
// function type selects the POSIX call rather than the struct initializer.
func checkpointFlock(_ descriptor: Int32, _ operation: Int32) -> Int32 {
    let call: (Int32, Int32) -> Int32 = flock
    return call(descriptor, operation)
}
