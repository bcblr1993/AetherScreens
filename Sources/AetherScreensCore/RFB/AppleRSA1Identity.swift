import Foundation
import Security
import CryptoKit

/// Local RSA1 identity construction. Key validity is not host trust;
/// authenticated SRP proofs remain required before accepting a session.
enum AppleRSA1Identity {
    enum Failure: Error { case invalidKey, invalidIdentity, encryptionFailed }
    struct ValidatedKey {
        fileprivate let key: SecKey
        let fingerprint: Data
    }

    static func validateSubjectPublicKeyInfo(_ der: Data) throws -> ValidatedKey {
        guard der.count <= AppleRSA1Prelude.maximumResponseBytes else { throw Failure.invalidKey }
        var outer = DER(der)
        var sequence = DER(try outer.read(0x30))
        guard outer.finished else { throw Failure.invalidKey }
        // rsaEncryption with explicit NULL parameters, as returned by the peer.
        let algorithm = try sequence.read(0x30)
        guard algorithm == Data([6,9,42,134,72,134,247,13,1,1,1,5,0]) else { throw Failure.invalidKey }
        let bits = try sequence.read(0x03)
        guard sequence.finished, bits.first == 0 else { throw Failure.invalidKey }
        let pkcs1 = Data(bits.dropFirst())
        var keyEnvelope = DER(pkcs1)
        var components = DER(try keyEnvelope.read(0x30))
        guard keyEnvelope.finished else { throw Failure.invalidKey }
        let modulus = try components.read(0x02), exponent = try components.read(0x02)
        // This independently implemented wire profile supports RSA-2048 only.
        guard components.finished, modulus.count == 257, modulus.first == 0,
              modulus[1] >= 128, modulus.last.map({ $0 & 1 == 1 }) == true,
              (1...4).contains(exponent.count), exponent.first != 0,
              exponent.first.map({ $0 < 128 }) == true else { throw Failure.invalidKey }
        let e = exponent.reduce(0) { $0 << 8 | Int($1) }
        guard e >= 3, e & 1 == 1 else { throw Failure.invalidKey }
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: 2048
        ] as CFDictionary, nil), SecKeyGetBlockSize(key) == 256,
              SecKeyIsAlgorithmSupported(key, .encrypt, .rsaEncryptionPKCS1) else { throw Failure.invalidKey }
        return ValidatedKey(key: key, fingerprint: Data(SHA256.hash(data: der)))
    }

    static func identityPacket(username: String, key: ValidatedKey) throws -> Data {
        let name = Data(username.utf8)
        guard !name.isEmpty, name.count <= 234, !name.contains(0) else { throw Failure.invalidIdentity }
        var plaintext = Data()
        append32(7 + name.count, to: &plaintext)
        append32(name.count, to: &plaintext)
        plaintext.append(name); plaintext.append(contentsOf: [0,0,0])
        guard let encrypted = SecKeyCreateEncryptedData(key.key, .rsaEncryptionPKCS1,
            plaintext as CFData, nil) as Data?, encrypted.count == 256 else { throw Failure.encryptionFailed }
        var packet = Data([0,0,2,138,1,0,82,83,65,49,0,2,1,0])
        packet.append(encrypted); packet.append(Data(repeating: 0, count: 384))
        return packet
    }

    private static func append32(_ value: Int, to data: inout Data) {
        var word = UInt32(value).bigEndian
        withUnsafeBytes(of: &word) { data.append(contentsOf: $0) }
    }

    private struct DER {
        let bytes: [UInt8]
        var position = 0
        init(_ data: Data) { bytes = Array(data) }
        var finished: Bool { position == bytes.count }
        mutating func read(_ tag: UInt8) throws -> Data {
            guard position + 2 <= bytes.count, bytes[position] == tag else { throw Failure.invalidKey }
            let lead = bytes[position + 1]; position += 2
            var length = Int(lead)
            if lead & 128 != 0 {
                let count = Int(lead & 127)
                guard (1...4).contains(count), count <= bytes.count - position,
                      bytes[position] != 0 else { throw Failure.invalidKey }
                length = 0
                for _ in 0..<count { length = length << 8 | Int(bytes[position]); position += 1 }
                guard length >= 128 else { throw Failure.invalidKey }
            }
            guard length <= bytes.count - position else { throw Failure.invalidKey }
            let result = Data(bytes[position..<(position + length)])
            position += length
            return result
        }
    }
}
