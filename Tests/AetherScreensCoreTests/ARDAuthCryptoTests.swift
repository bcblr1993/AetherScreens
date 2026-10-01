import XCTest
import BigInt
import CryptoKit
import CommonCrypto
@testable import AetherScreensCore

final class ARDAuthCryptoTests: XCTestCase {
    func testCredentialBlockCanBeDecryptedByPeer() throws {
        let prime = BigUInt("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFF61", radix: 16)!
        let serverSecret = BigUInt(23)
        let serverPublic = BigUInt(5).power(serverSecret, modulus: prime)
        let response = try ARDAuthCrypto.response(generator: 5,
            prime: ARDAuthCrypto.padded(prime, length: 16),
            peer: ARDAuthCrypto.padded(serverPublic, length: 16),
            username: "qa-user", password: "fixture-password")
        XCTAssertEqual(response.count, 144)
        let clientPublic = BigUInt(response.suffix(16))
        let shared = clientPublic.power(serverSecret, modulus: prime)
        let key = Array(Insecure.MD5.hash(data: ARDAuthCrypto.padded(shared, length: 16)))
        let ciphertext = Array(response.prefix(128))
        var plaintext = [UInt8](repeating: 0, count: 128)
        var written = 0
        let status = CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
            CCOptions(kCCOptionECBMode), key, key.count, nil, ciphertext,
            ciphertext.count, &plaintext, plaintext.count, &written)
        XCTAssertEqual(status, CCCryptorStatus(kCCSuccess))
        XCTAssertEqual(written, 128)
        XCTAssertEqual(String(bytes: plaintext.prefix(7), encoding: .utf8), "qa-user")
        XCTAssertEqual(plaintext[7], 0)
        XCTAssertEqual(String(bytes: plaintext[64..<80], encoding: .utf8), "fixture-password")
        XCTAssertEqual(plaintext[80], 0)
    }

    func testRejectsUnsafePeerAndOversizedCredentials() throws {
        let prime = Data(repeating: 0xFF, count: 16)
        XCTAssertThrowsError(try ARDAuthCrypto.response(generator: 5, prime: prime,
            peer: Data(repeating: 0, count: 16), username: "qa", password: "fixture"))
        let peer = Data(repeating: 0, count: 15) + Data([5])
        XCTAssertThrowsError(try ARDAuthCrypto.response(generator: 5, prime: prime,
            peer: peer, username: String(repeating: "a", count: 64), password: "fixture"))
        XCTAssertThrowsError(try ARDAuthCrypto.response(generator: 5,
            prime: Data(repeating: 0xFF, count: 513), peer: Data(repeating: 5, count: 513),
            username: "qa", password: "fixture"))
    }
}
