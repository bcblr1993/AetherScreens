import Foundation
import CryptoKit
import NIOSSH

/// Bounded key-file decoding. Imported bytes remain in memory or the SSH vault;
/// they never enter device defaults, logs or error messages.
public enum SSHPrivateKey {
    public enum Failure: Error, Equatable, LocalizedError {
        case invalid, encrypted, unsupported, tooLarge, missing
        public var errorDescription: String? {
            switch self {
            case .missing: return AppLocalization.string("The SSH private key is missing. Import it again.")
            case .invalid: return AppLocalization.string("The SSH private key is invalid or damaged.")
            case .encrypted: return AppLocalization.string("Encrypted SSH key files are not supported yet.")
            case .unsupported: return AppLocalization.string("Use an Ed25519 or ECDSA SSH private key.")
            case .tooLarge: return AppLocalization.string("The SSH key file exceeds 64 KB.")
            }
        }
    }
    public static let maximumSize = 64 * 1024

    public static func decode(_ data: Data) throws -> NIOSSHPrivateKey {
        guard data.count <= maximumSize else { throw Failure.tooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw Failure.invalid }
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        if lines.contains("-----BEGIN ENCRYPTED PRIVATE KEY-----") || lines.contains(where: {
            $0.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\t", with: "") == "Proc-Type:4,ENCRYPTED"
        }) { throw Failure.encrypted }
        if text.contains("-----BEGIN OPENSSH PRIVATE KEY-----") { return try openSSH(text) }
        if text.contains("-----BEGIN RSA PRIVATE KEY-----") { throw Failure.unsupported }
        // CryptoKit verifies the ASN.1 algorithm/curve and scalar bounds.
        if text.contains("-----BEGIN EC PRIVATE KEY-----") || text.contains("-----BEGIN PRIVATE KEY-----") {
            if let key = try? P256.Signing.PrivateKey(pemRepresentation: text) { return .init(p256Key: key) }
            if let key = try? P384.Signing.PrivateKey(pemRepresentation: text) { return .init(p384Key: key) }
            if let key = try? P521.Signing.PrivateKey(pemRepresentation: text) { return .init(p521Key: key) }
        }
        throw Failure.invalid
    }

    public static func fingerprint(_ key: NIOSSHPrivateKey) throws -> String {
        let parts = String(openSSHPublicKey: key.publicKey).split(separator: " ")
        guard parts.count >= 2, let blob = Data(base64Encoded: String(parts[1])) else { throw Failure.invalid }
        return "SHA256:" + Data(SHA256.hash(data: blob)).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }

    private static func openSSH(_ text: String) throws -> NIOSSHPrivateKey {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.first == "-----BEGIN OPENSSH PRIVATE KEY-----", lines.last == "-----END OPENSSH PRIVATE KEY-----",
              let data = Data(base64Encoded: lines.dropFirst().dropLast().joined()), data.starts(with: Data("openssh-key-v1\0".utf8)) else { throw Failure.invalid }
        var outer = Reader(Array(data.dropFirst(15)))
        let cipher = try outer.string(), kdf = try outer.string(), options = try outer.bytes()
        guard cipher == "none", kdf == "none" else { throw Failure.encrypted }
        guard options.isEmpty, try outer.number() == 1 else { throw Failure.invalid }
        let publicBlob = try outer.bytes(), privateBlob = try outer.bytes()
        guard outer.remaining == 0, privateBlob.count % 8 == 0 else { throw Failure.invalid }
        var inner = Reader(Array(privateBlob))
        guard try inner.number() == inner.number() else { throw Failure.invalid }
        let algorithm = try inner.string()
        let key: NIOSSHPrivateKey
        do {
            switch algorithm {
            case "ssh-ed25519":
                let publicBytes = try inner.bytes(), secret = try inner.bytes()
                guard publicBytes.count == 32, secret.count == 64, secret.suffix(32) == publicBytes else { throw Failure.invalid }
                let decoded = try Curve25519.Signing.PrivateKey(rawRepresentation: secret.prefix(32))
                guard decoded.publicKey.rawRepresentation == publicBytes else { throw Failure.invalid }
                key = .init(ed25519Key: decoded)
            case "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521":
                let curve = try inner.string(), publicBytes = try inner.bytes()
                guard algorithm == "ecdsa-sha2-" + curve else { throw Failure.invalid }
                let length = curve == "nistp256" ? 32 : curve == "nistp384" ? 48 : 66
                let scalar = try inner.scalar(length: length)
                switch curve {
                case "nistp256":
                    let decoded = try P256.Signing.PrivateKey(rawRepresentation: scalar)
                    guard decoded.publicKey.x963Representation == publicBytes else { throw Failure.invalid }
                    key = .init(p256Key: decoded)
                case "nistp384":
                    let decoded = try P384.Signing.PrivateKey(rawRepresentation: scalar)
                    guard decoded.publicKey.x963Representation == publicBytes else { throw Failure.invalid }
                    key = .init(p384Key: decoded)
                case "nistp521":
                    let decoded = try P521.Signing.PrivateKey(rawRepresentation: scalar)
                    guard decoded.publicKey.x963Representation == publicBytes else { throw Failure.invalid }
                    key = .init(p521Key: decoded)
                default: throw Failure.unsupported
                }
            default: throw Failure.unsupported
            }
        } catch let failure as Failure { throw failure }
        catch { throw Failure.invalid }
        _ = try inner.bytes() // comment is deliberately neither persisted nor logged
        let padding = inner.tail
        guard (0...8).contains(padding.count), padding.enumerated().allSatisfy({ $0.element == UInt8($0.offset + 1) }) else { throw Failure.invalid }
        let encoded = String(openSSHPublicKey: key.publicKey).split(separator: " ")
        guard encoded.count >= 2, Data(base64Encoded: String(encoded[1])) == publicBlob else { throw Failure.invalid }
        return key
    }

    private struct Reader {
        let data: [UInt8]
        var offset = 0
        init(_ data: [UInt8]) { self.data = data }
        var remaining: Int { data.count - offset }
        var tail: ArraySlice<UInt8> { data[offset...] }
        mutating func number() throws -> UInt32 {
            guard remaining >= 4 else { throw Failure.invalid }
            defer { offset += 4 }
            return data[offset..<offset + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        }
        mutating func bytes() throws -> Data {
            let count = Int(try number())
            guard count <= remaining else { throw Failure.invalid }
            defer { offset += count }
            return Data(data[offset..<offset + count])
        }
        mutating func string() throws -> String {
            guard let result = String(data: try bytes(), encoding: .utf8) else { throw Failure.invalid }
            return result
        }
        mutating func scalar(length: Int) throws -> Data {
            var value = try bytes()
            guard !value.isEmpty, value.first! & 0x80 == 0 else { throw Failure.invalid }
            if value.count > 1 && value.first == 0 {
                guard value[value.startIndex + 1] & 0x80 != 0 else { throw Failure.invalid }
                value.removeFirst()
            }
            guard value.count <= length else { throw Failure.invalid }
            return Data(repeating: 0, count: length - value.count) + value
        }
    }
}
