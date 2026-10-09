import Foundation
import CryptoKit
import CommonCrypto
import Security
import BigInt

/// Apple security type 30: DH, MD5-derived AES-128 credential block.
/// Only authentication is protected; use a trusted LAN or Tailscale for the session.
enum ARDAuthCrypto {
    enum Failure: Error { case invalidChallenge, credentialTooLong, randomFailed, encryptionFailed }

    /// Secret material stays with the caller's in-memory experimental handshake.
    struct Exchange {
        let response: Data
        let wrapKey: Data
    }

    static func response(generator: UInt16, prime: Data, peer: Data, username: String, password: String) throws -> Data {
        try exchange(generator: generator, prime: prime, peer: peer,
                     username: username, password: password).response
    }

    static func exchange(generator: UInt16, prime: Data, peer: Data, username: String, password: String) throws -> Exchange {
        guard (16...512).contains(prime.count), peer.count == prime.count else { throw Failure.invalidChallenge }
        let modulus = BigUInt(prime), serverKey = BigUInt(peer)
        guard modulus.bitWidth >= 127, modulus & 1 == 1, generator > 1,
              BigUInt(generator) < modulus, serverKey > 1, serverKey < modulus - 1 else {
            throw Failure.invalidChallenge
        }
        let user = Array(username.utf8), pass = Array(password.utf8)
        guard user.count <= 63, pass.count <= 63, !user.contains(0), !pass.contains(0) else {
            throw Failure.credentialTooLong
        }
        // A 256-bit private exponent supplies 128-bit work factor without a 4096-bit exponent.
        var random = [UInt8](repeating: 0, count: min(prime.count, 32))
        guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else {
            throw Failure.randomFailed
        }
        let exponent = BigUInt(Data(random)) % (modulus - 3) + 2
        let publicKey = BigUInt(generator).power(exponent, modulus: modulus)
        let secret = padded(serverKey.power(exponent, modulus: modulus), length: prime.count)
        let key = Array(Insecure.MD5.hash(data: secret))
        var credentials = [UInt8](repeating: 0, count: 128)
        guard SecRandomCopyBytes(kSecRandomDefault, credentials.count, &credentials) == errSecSuccess else {
            throw Failure.randomFailed
        }
        credentials.replaceSubrange(0..<user.count, with: user)
        credentials[user.count] = 0
        credentials.replaceSubrange(64..<(64 + pass.count), with: pass)
        credentials[64 + pass.count] = 0
        var encrypted = [UInt8](repeating: 0, count: 128)
        var written = 0
        let status = CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                             CCOptions(kCCOptionECBMode), key, key.count, nil,
                             credentials, credentials.count, &encrypted, encrypted.count, &written)
        guard status == kCCSuccess, written == 128 else { throw Failure.encryptionFailed }
        return Exchange(response: Data(encrypted) + padded(publicKey, length: prime.count),
                        wrapKey: Data(key))
    }

    static func padded(_ value: BigUInt, length: Int) -> Data {
        let data = value.serialize()
        return Data(repeating: 0, count: max(0, length - data.count)) + data
    }
}
