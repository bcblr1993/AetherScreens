import XCTest
@testable import AetherScreensCore

final class AppleSRP6aProofTests:XCTestCase {
    func testIndependentPaddedGeneratorVectorAndM2Gate() throws {
        let challenge = try AppleSRPChallenge(frame: fixture())
        let result = try AppleSRP6aProof.compute(challenge: challenge, password: "fixture-password",
            privateExponent: hex("0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"), tokenPadding: .groupWidth)
        XCTAssertEqual(result.clientProof, hex("344e7822a7971a1a46a38b974dc8e2f6370c1e68523e01c7dd98b11d9a2d11aca66938a79a7f80d5985ada23d70d47a1b0143f438c484427ef18497fdad1ee35"))
        let server = hex("1b8a36ed4b9781ea8aea91657eec9680889c75dfc97d7e51895701e6f1ad8126c67c6d6393c23836d1cad782ecae00a8d240bd229f86f56cb21da4f97e2f00cb")
        XCTAssertEqual(try result.verifiedWrapKey(serverProof: server), hex("bd9514274302fe2ae84b0696797423d0"))
        for index in server.indices {
            var changed = server; changed[index] ^= 1
            XCTAssertThrowsError(try result.verifiedWrapKey(serverProof: changed))
        }
        // The alternate token convention must not authenticate this transcript.
        XCTAssertThrowsError(try result.verifiedWrapKey(serverProof: hex("7d9a9827a9e650325439864ead8e1cdf9f7694a87258637a67ea42e5be87cfc4349d6157f144596533432a35b5e95c452a950ff809ede903047510065bcaf30f")))
    }
    func testIndependentPythonClientAndServerVectorAndProofGate() throws {
        let frame=fixture()
        let challenge=try AppleSRPChallenge(frame:frame)
        let result=try AppleSRP6aProof.compute(challenge:challenge,password:"fixture-password",privateExponent:hex("0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"))
        XCTAssertEqual(result.clientPublic,hex("db34e0e99354a701a59724e4f3304131ba7ed421ff13034f3f0ad002fb5dd2c839d0f11dddd9de352901fdb31dc4f73e21cbea0265e114aca2e46b9ebfd13b21a2bc27fd3477cc68f7d85ad2ed2f9a4e6602e720d79c825d5066f0f0ba295535f7be6723192e420cb40d24bd13665c3a00047a88f317043a7521c861681531120b69cc6414a458a7378c90cc98bfa68c7c6aea264d2821177e2978acf8672040423a1cad2a3dbaeae8f53e2a31b170d6479bfe6411f59b2fba0241b38423997a858303b2d11c91b82843d23adcd0bbfa1fb4414b922a9e16adddce8187fdb4d2ad65b8b56933532cff3cce5771cbabfbaa7f337541eb09c0590856df9cff67f76e4f83fb6b92c8a5bc6130b1f98c02b7b43e6aa93243c1450d60ea25d921f3d5401394cf19dc3e2aec143b86de29d889ddea9398644f3d63ebf2c917b64fef5440f6122b28a57e6afb4c7fd0de960b43602773f57e027c2fb809bb8c85d601278099347b46fe59b795a3108685d4516f24ec318fc94db99d5580d830c21d33106fa03233dea59143493e7ca73959dd9ccc683e2ef7e558d7a878f2aa4303c84b4314b9e17ec9eccdfbbbafac4dccabffb2b1109cbb10a0f76768b4e42f47341a76df44b36eb1de3268180d9806acba263c1b3e0c9bcb615f6da7320f12a4eb0405431d07c04c4acc081690455005097ee240a0c066e306c6b584c2a3dd5132d6"))
        XCTAssertEqual(result.clientProof,hex("77de831a8d629ebf336c108cbbc78753fed883750def9ee2adc2f8bccc3ab5e4ee2e5e0b028acaa28c1f944d543ea276324936313f14ba0689e16f2c307fe776"))
        let server=hex("7d9a9827a9e650325439864ead8e1cdf9f7694a87258637a67ea42e5be87cfc4349d6157f144596533432a35b5e95c452a950ff809ede903047510065bcaf30f")
        XCTAssertEqual(try result.verifiedWrapKey(serverProof:server),hex("bd9514274302fe2ae84b0696797423d0"))
        for index in server.indices {
            var changed=server; changed[index]^=1
            XCTAssertThrowsError(try result.verifiedWrapKey(serverProof:changed))
        }
        XCTAssertThrowsError(try result.verifiedWrapKey(serverProof:Data(server.dropLast())))
        XCTAssertThrowsError(try result.verifiedWrapKey(serverProof:server+Data([0])))
    }
    func testUntrustedGroupAndDegeneratePeerAreRejectedBeforePasswordWork() throws {
        let group=AppleSRP6aProof.group
        var changed=group; changed[0]^=1
        for frame in [fixture(modulus:changed),fixture(peer:Data(repeating:0,count:512)),fixture(peer:group),fixture(optionsText:"mda=SHA-256")] {
            let challenge=try AppleSRPChallenge(frame:frame)
            XCTAssertThrowsError(try AppleSRP6aProof.compute(challenge:challenge,password:"fixture-password"))
        }
        let challenge=try AppleSRPChallenge(frame:fixture())
        XCTAssertThrowsError(try AppleSRP6aProof.compute(challenge:challenge,password:"fixture-password",privateExponent:Data(repeating:0,count:32)))
        XCTAssertThrowsError(try AppleSRP6aProof.compute(challenge:challenge,password:String(repeating:"a",count:1025)))
    }
    private func fixture(modulus:Data?=nil,peer:Data?=nil,optionsText:String="mda=SHA-512,replay_detection,conf+int=ChaCha20-Poly1305,kdf=SALTED-SHA512-PBKDF2")->Data {
        let n=modulus ?? hex("FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F83655D23DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804F1746C08CA18217C32905E462E36CE3BE39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9DE2BCBF6955817183995497CEA956AE515D2261898FA051015728E5A8AAAC42DAD33170D04507A33A85521ABDF1CBA64ECFB850458DBEF0A8AEA71575D060C7DB3970F85A6E1E4C7ABF5AE8CDB0933D71E8C94E04A25619DCEE3D2261AD2EE6BF12FFA06D98A0864D87602733EC86A64521F2B18177B200CBBE117577A615D6C770988C0BAD946E208E24FA074E5AB3143DB5BFCE0FD108E4B82D120A92108011A723C12A787E6D788719A10BDBA5B2699C327186AF4E23C1A946834B6150BDA2583E9CA2AD44CE8DBBBC2DB04DE8EF92E8EFC141FBECAA6287C59474E6BC05D99B2964FA090C3A2233BA186515BE7ED1F612970CEE2D7AFB81BDD762170481CD0069127D5B05AA993B4EA988D8FDDC186FFB7DC90A6C08F4DF435C934063199FFFFFFFFFFFFFFFF"), b=peer ?? hex("78a1635aab6c48bcbd4ef51ec0b408920d8d5e69e3614f698b5e756d5c290717d84186b4ffbad2deb9c546937c301963f6e9f8866a0abd9cc428a37c3c6ece8bcee66819c1630ea61c261ec12b20892e18cb5e5ad26eb6c36e0bcc22f351c3701bf0fd482476356fb9566e3bf46b442de111d3b028958271461d8893d2ad5ef401b13756021cd7581f6274201155f704925811a7c8eae2046eade37a7e8eb2de3a352873f864051a77ba9a503c8c184e00ec2bf1bf4faaa602d38f5d422965b9b0aed7b0f6ac325cbce1cb9dc942bba110a235bd1365b44f2b94c26c31b1ceff668b3aeae0d535c276869972daf675d6164b1cee2f5a751609316b32fda6666ca017024376594c4a6d0e17c71f5331c9f9d7935044b66a42c96f08a620fb196c635b7daff55e156c52a44b4a31e1100190f3d15ec5fcdfcbfe41c8a9ee6aae9162278cbc78f6f8fe0572bf619fc037e7b2a765b7f960440f08491ac67f0e39ead2fd88f2e66b5d774e426d219f0ebaeb74c5d26237f2135241c295976bb3c298a82a89d980022f672f0314b153eea06ac534318f5d6424f02b5258d1d338d9e31ba48c00715b80eb855a2fc26b6e99e28c2cf86f5c5c9ccee94f19e40d16a396b457e43a8361560a295315872a84902a7549332e798eb2e79a2ddbdf46cc005105d06230190b243aac51eb00dcfdcff2b24eb9693365fe8b08bc05d73687d092"), salt=hex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
        let options=Data(optionsText.utf8)
        var payload=Data([0])
        for part in [word(UInt64(n.count),2),n,Data([0,1,5,32]),salt,word(UInt64(b.count),2),b,word(10,8),word(UInt64(options.count),2),options] { payload.append(part) }
        var frame=word(UInt64(payload.count+10),4)
        for part in [word(2,4),word(UInt64(payload.count+4),2),word(UInt64(payload.count),4),payload] { frame.append(part) }
        return frame
    }
    private func word(_ value:UInt64,_ count:Int)->Data {
        Data((0..<count).reversed().map { UInt8(truncatingIfNeeded:value>>($0*8)) })
    }
    private func hex(_ string:String)->Data {
        Data(stride(from:0,to:string.count,by:2).map { offset in
            let index=string.index(string.startIndex,offsetBy:offset)
            return UInt8(string[index..<string.index(index,offsetBy:2)],radix:16)!
        })
    }
}
