import XCTest
@testable import AetherScreensCore

final class AppleSRPProofPacketTests: XCTestCase {
    func testMeaningfulPacketFieldsAndExactConsumption() throws {
        let publicValue = Data(repeating: 0xa5, count: 512)
        let proof = Data(repeating: 0x6b, count: 64)
        let random = Data(0..<16)
        let packet = try AppleSRPProofPacket.encode(clientPublic: publicValue,
            clientProof: proof, options: AppleSRP6aProof.supportedOptions, clientRandom: random)
        // Independent expected header: 678-byte inner, 682-byte body; no tail.
        XCTAssertEqual(packet.prefix(18), Data([0,0,2,180,1,0,82,83,65,49,0,2,2,170,0,0,2,166]))
        XCTAssertEqual(packet.count, 696)
        XCTAssertEqual(packet[18..<20], Data([2,0]))
        XCTAssertEqual(packet[20..<532], publicValue)
        XCTAssertEqual(packet[532], 64)
        XCTAssertEqual(packet[533..<597], proof)
        XCTAssertEqual(packet[597..<599], Data([0,80]))
        XCTAssertEqual(String(data: packet[599..<679], encoding: .utf8),
            "mda=SHA-512,replay_detection,conf+int=ChaCha20-Poly1305,kdf=SALTED-SHA512-PBKDF2")
        XCTAssertEqual(packet[679], 16)
        XCTAssertEqual(packet[680..<696], random)
    }

    func testRejectsInvalidFixedFields() {
        let a = Data(repeating: 1, count: 512), m = Data(repeating: 2, count: 64)
        for size in [0, 511, 513] {
            XCTAssertThrowsError(try AppleSRPProofPacket.encode(clientPublic: Data(count: size),
                clientProof: m, options: AppleSRP6aProof.supportedOptions))
        }
        XCTAssertThrowsError(try AppleSRPProofPacket.encode(clientPublic: a,
            clientProof: Data(count: 63), options: AppleSRP6aProof.supportedOptions))
        XCTAssertThrowsError(try AppleSRPProofPacket.encode(clientPublic: a,
            clientProof: m, options: "unknown"))
        for size in [0, 15, 17] {
            XCTAssertThrowsError(try AppleSRPProofPacket.encode(clientPublic: a,
                clientProof: m, options: AppleSRP6aProof.supportedOptions, clientRandom: Data(count: size)))
        }
    }
}
