import Foundation
import NIO
import Crypto
import Citadel

/// Checks public OpenSSH container metadata before invoking the expensive KDF.
/// The imported private material is neither logged nor serialized by this helper.
public enum SSHPrivateKeyCost {
    public static func validate(_ text: String) throws {
        func rejected() -> SSHRemoteSession.ConfigurationError { .invalidPrivateKey }
        let lines = text.split(whereSeparator: { $0.isNewline }).map { $0.trimmingCharacters(in: .whitespaces) }
        guard text.utf8.count <= 65536, lines.first == "-----BEGIN OPENSSH PRIVATE KEY-----",
              lines.last == "-----END OPENSSH PRIVATE KEY-----",
              let data = Data(base64Encoded: lines.dropFirst().dropLast().joined()) else { throw rejected() }
        var buffer = ByteBuffer(bytes: data)
        let magic = Array("openssh-key-v1\0".utf8)
        guard buffer.readBytes(length: magic.count) == magic else { throw rejected() }
        func field(_ input: inout ByteBuffer) -> [UInt8]? {
            guard let size: UInt32 = input.readInteger(), size <= 65536 else { return nil }
            return input.readBytes(length: Int(size))
        }
        guard let cipher = field(&buffer), let kdf = field(&buffer), let options = field(&buffer) else { throw rejected() }
        if kdf == Array("none".utf8) {
            guard cipher == Array("none".utf8), options.isEmpty else { throw rejected() }
        } else {
            guard kdf == Array("bcrypt".utf8),
                  [Array("aes128-ctr".utf8), Array("aes256-ctr".utf8)].contains(cipher) else { throw rejected() }
            var options = ByteBuffer(bytes: options)
            guard let salt = field(&options), !salt.isEmpty,
                  let rounds: UInt32 = options.readInteger(), (1...256).contains(rounds),
                  options.readableBytes == 0 else { throw rejected() }
        }
        guard let count: UInt32 = buffer.readInteger(), count == 1,
              let publicBytes = field(&buffer), let privateBytes = field(&buffer),
              buffer.readableBytes == 0, !privateBytes.isEmpty else { throw rejected() }
        var publicKey = ByteBuffer(bytes: publicBytes)
        guard field(&publicKey) == Array("ssh-ed25519".utf8),
              field(&publicKey)?.count == 32, publicKey.readableBytes == 0 else { throw rejected() }
        let blockSize = cipher == Array("none".utf8) ? 8 : 16
        guard privateBytes.count % blockSize == 0 else { throw rejected() }
        // Plain keys can be fully checked without a password or expensive KDF.
        // Encrypted contents are checked later when the user supplies a passphrase.
        if cipher == Array("none".utf8),
           (try? Curve25519.Signing.PrivateKey(sshEd25519: text)) == nil { throw rejected() }
    }
}
