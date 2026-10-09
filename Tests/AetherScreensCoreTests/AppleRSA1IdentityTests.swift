import XCTest
import Security
@testable import AetherScreensCore

final class AppleRSA1IdentityTests: XCTestCase {
    func testIdentityDecryptsToIndependentUTF8FixtureAndRejectsInvalidInputs() throws {
        var error: Unmanaged<CFError>?
        let privateKey = try XCTUnwrap(SecKeyCreateRandomKey([
            kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048,
            kSecPrivateKeyAttrs: [kSecAttrIsPermanent: false]
        ] as CFDictionary, &error))
        let publicKey = try XCTUnwrap(SecKeyCopyPublicKey(privateKey))
        let pkcs1 = try XCTUnwrap(SecKeyCopyExternalRepresentation(publicKey, &error) as Data?)
        let algorithm = Data([0x30,13,6,9,42,134,72,134,247,13,1,1,1,5,0])
        let spki = tlv(0x30, algorithm + tlv(3, Data([0]) + pkcs1))
        let key = try AppleRSA1Identity.validateSubjectPublicKeyInfo(spki)
        XCTAssertEqual(key.fingerprint.count,32)
        let packet = try AppleRSA1Identity.identityPacket(username:"qa🙂", key:key)
        XCTAssertEqual(packet.count,654)
        XCTAssertEqual(Data(packet.prefix(14)),Data([0,0,2,138,1,0,82,83,65,49,0,2,1,0]))
        XCTAssertEqual(Data(packet.suffix(384)),Data(repeating:0,count:384))
        let plaintext = try XCTUnwrap(SecKeyCreateDecryptedData(privateKey, .rsaEncryptionPKCS1,
            packet.subdata(in:14..<270) as CFData, &error) as Data?)
        XCTAssertEqual(plaintext,Data([0,0,0,13,0,0,0,6]) + Data("qa🙂".utf8) + Data([0,0,0]))
        for name in ["", "qa\0user", String(repeating:"a",count:235)] {
            XCTAssertThrowsError(try AppleRSA1Identity.identityPacket(username:name,key:key))
        }
        XCTAssertNoThrow(try AppleRSA1Identity.identityPacket(username:String(repeating:"a",count:234),key:key))
        for malformed in [spki + Data([0]),Data(spki.dropLast()),Data([0x30,0x80]),Data(repeating:0,count:8193)] {
            XCTAssertThrowsError(try AppleRSA1Identity.validateSubjectPublicKeyInfo(malformed))
        }
        var wrongAlgorithm = spki
        let oid = try XCTUnwrap(wrongAlgorithm.range(of: Data([42,134,72,134,247,13,1,1,1])))
        wrongAlgorithm[oid.lowerBound] ^= 1
        XCTAssertThrowsError(try AppleRSA1Identity.validateSubjectPublicKeyInfo(wrongAlgorithm))
    }
    private func tlv(_ tag: UInt8,_ body:Data)->Data {
        var header=Data([tag])
        if body.count < 128 { header.append(UInt8(body.count)) }
        else { header.append(contentsOf:[0x82,UInt8(body.count>>8),UInt8(body.count&255)]) }
        return header+body
    }
}
