import XCTest
@testable import AetherScreensCore

final class VNCAuthCryptoTests: XCTestCase {

    func testBitReversal() {
        XCTAssertEqual(VNCAuthCrypto.reverseBits(in: 0b10000000), 0b00000001)
        XCTAssertEqual(VNCAuthCrypto.reverseBits(in: 0b00000001), 0b10000000)
        XCTAssertEqual(VNCAuthCrypto.reverseBits(in: 0b10101010), 0b01010101)
        XCTAssertEqual(VNCAuthCrypto.reverseBits(in: 0x00), 0x00)
        XCTAssertEqual(VNCAuthCrypto.reverseBits(in: 0xFF), 0xFF)
        XCTAssertEqual(VNCAuthCrypto.reverseBits(in: 0b11000011), 0b11000011)
    }

    func testKeyPreparation() {
        // Password shorter than 8 bytes should be padded with 0
        let shortPwd = "abc"
        let key = VNCAuthCrypto.prepareKey(from: shortPwd)
        XCTAssertEqual(key.count, 8)
        XCTAssertEqual(key[0], VNCAuthCrypto.reverseBits(in: Character("a").asciiValue!))
        XCTAssertEqual(key[1], VNCAuthCrypto.reverseBits(in: Character("b").asciiValue!))
        XCTAssertEqual(key[2], VNCAuthCrypto.reverseBits(in: Character("c").asciiValue!))
        XCTAssertEqual(key[3], 0)
        XCTAssertEqual(key[7], 0)

        // Password longer than 8 bytes should be truncated
        let longPwd = "1234567890extra"
        let longKey = VNCAuthCrypto.prepareKey(from: longPwd)
        XCTAssertEqual(longKey.count, 8)
        XCTAssertEqual(longKey[7], VNCAuthCrypto.reverseBits(in: Character("8").asciiValue!))
    }

    func testVNCChallengeEncryption() {
        let challenge = Data(repeating: 0x42, count: 16)
        let response = VNCAuthCrypto.encryptChallenge(challenge, password: "mypassword")

        XCTAssertEqual(response.count, 16)
        // Challenge encryption must be deterministic
        let response2 = VNCAuthCrypto.encryptChallenge(challenge, password: "mypassword")
        XCTAssertEqual(response, response2)

        // Different password yields different response
        let responseDiff = VNCAuthCrypto.encryptChallenge(challenge, password: "otherpassword")
        XCTAssertNotEqual(response, responseDiff)
    }

    func testDESCipherKnownVector() {
        // Standard DES test vector from NBS SP 800-20
        // Key: 0x0123456789ABCDEF
        let key: [UInt8] = [0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]
        // Plaintext: "Now is  " (0x4E6F772069732020)
        let plaintext: [UInt8] = [0x4E, 0x6F, 0x77, 0x20, 0x69, 0x73, 0x20, 0x20]
        // Standard DES ECB output (matches Apple CommonCrypto CCCrypt DES ECB)
        let expected: [UInt8] = [160, 23, 177, 163, 233, 121, 121, 249]

        let cipher = DESCipher(key: key)
        let encrypted = cipher.encryptBlock(plaintext)
        XCTAssertEqual(encrypted, expected)
    }
}
