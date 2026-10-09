import Foundation
import CryptoKit

/// Identity metadata for a public key already validated by the SSH transport.
/// This type is not a cryptographic key parser or signature verifier.
public struct SSHHostKey: Codable, Equatable, Sendable {
    public let blob: Data
    public var fingerprint: String {
        "SHA256:" + Data(SHA256.hash(data: blob)).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }

    public init(validatedKeyBlob blob: Data) throws {
        guard blob.count >= 8, blob.count <= 65536 else { throw SSHHostTrustStore.Failure.invalidKey }
        let bytes = Array(blob.prefix(4))
        let length = bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0, length <= 256, Int(length) + 4 < blob.count,
              blob.dropFirst(4).prefix(Int(length)).allSatisfy({ $0 > 32 && $0 < 127 }) else {
            throw SSHHostTrustStore.Failure.invalidKey
        }
        self.blob = blob
    }

    private enum CodingKeys: String, CodingKey { case blob }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(validatedKeyBlob: values.decode(Data.self, forKey: .blob))
    }
}

/// Host-key changes need a decision against the exact key shown to the user.
/// Damaged persistence fails closed rather than treating every host as new.
public final class SSHHostTrustStore: @unchecked Sendable {
    public static let shared = SSHHostTrustStore()
    public static let storageKey = "aetherscreens.ssh.known-hosts.v1"
    public enum Assessment: Equatable, Sendable {
        case trusted
        case unknown
        case changed(previous: SSHHostKey)
    }
    public enum Failure: Error, Equatable { case invalidKey, damagedStorage, staleDecision }
    private let defaults: UserDefaults
    // Multiple store instances must share the read/compare/write lock.
    private static let lock = NSLock()

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func assess(_ key: SSHHostKey, at server: SSHServerAddress) throws -> Assessment {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard let previous = try read()[server.identity] else { return .unknown }
        return previous == key ? .trusted : .changed(previous: previous)
    }

    public func approve(_ key: SSHHostKey, at server: SSHServerAddress, replacing expected: SSHHostKey? = nil) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        var hosts = try read()
        if hosts[server.identity] == key { return }
        guard hosts[server.identity] == expected else { throw Failure.staleDecision }
        hosts[server.identity] = key
        defaults.set(try JSONEncoder().encode(hosts), forKey: Self.storageKey)
    }

    public func forget(_ server: SSHServerAddress, expected: SSHHostKey) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        var hosts = try read()
        guard hosts[server.identity] == expected else { throw Failure.staleDecision }
        hosts.removeValue(forKey: server.identity)
        defaults.set(try JSONEncoder().encode(hosts), forKey: Self.storageKey)
    }

    private func read() throws -> [String: SSHHostKey] {
        guard defaults.object(forKey: Self.storageKey) != nil else { return [:] }
        guard let data = defaults.data(forKey: Self.storageKey),
              let hosts = try? JSONDecoder().decode([String: SSHHostKey].self, from: data) else {
            throw Failure.damagedStorage
        }
        return hosts
    }
}
