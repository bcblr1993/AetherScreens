import Foundation
import CryptoKit
import CommonCrypto
import Security
import BigInt

/// Apple SHA512/PBKDF2 SRP math only; transport and algorithm negotiation remain
/// separate. This synchronous work belongs on the authentication worker.
enum AppleSRP6aProof {
    // Experimental QA distinction; server's exact variant is not yet verified.
    enum TokenPadding { case minimalGenerator, groupWidth }
    enum Failure: Error { case invalidParameters, randomFailed, derivationFailed, invalidServerProof }
    static let supportedOptions = "mda=SHA-512,replay_detection,conf+int=ChaCha20-Poly1305,kdf=SALTED-SHA512-PBKDF2"
    static let group = Data(stride(from:0,to:primeHex.count,by:2).map { offset in
        let start=primeHex.index(primeHex.startIndex,offsetBy:offset)
        return UInt8(primeHex[start..<primeHex.index(start,offsetBy:2)],radix:16)!
    })
    private static let primeHex = "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F83655D23DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804F1746C08CA18217C32905E462E36CE3BE39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9DE2BCBF6955817183995497CEA956AE515D2261898FA051015728E5A8AAAC42DAD33170D04507A33A85521ABDF1CBA64ECFB850458DBEF0A8AEA71575D060C7DB3970F85A6E1E4C7ABF5AE8CDB0933D71E8C94E04A25619DCEE3D2261AD2EE6BF12FFA06D98A0864D87602733EC86A64521F2B18177B200CBBE117577A615D6C770988C0BAD946E208E24FA074E5AB3143DB5BFCE0FD108E4B82D120A92108011A723C12A787E6D788719A10BDBA5B2699C327186AF4E23C1A946834B6150BDA2583E9CA2AD44CE8DBBBC2DB04DE8EF92E8EFC141FBECAA6287C59474E6BC05D99B2964FA090C3A2233BA186515BE7ED1F612970CEE2D7AFB81BDD762170481CD0069127D5B05AA993B4EA988D8FDDC186FFB7DC90A6C08F4DF435C934063199FFFFFFFFFFFFFFFF"
    struct Proof: Sendable {
        let clientPublic: Data
        let clientProof: Data
        fileprivate let expectedServerProof: Data
        fileprivate let pendingWrapKey: Data
        func verifiedWrapKey(serverProof:Data) throws -> Data {
            guard serverProof.count==64 else { throw Failure.invalidServerProof }
            var difference:UInt8=0
            for (a,b) in zip(serverProof,expectedServerProof) { difference |= a ^ b }
            guard difference==0 else { throw Failure.invalidServerProof }
            return pendingWrapKey
        }
    }
    static func compute(challenge:AppleSRPChallenge,password:String,privateExponent:Data?=nil,
                        tokenPadding:TokenPadding = .minimalGenerator) throws -> Proof {
        let n=BigUInt(group), g=BigUInt(5), peer=BigUInt(challenge.serverPublic)
        guard challenge.modulus==group, challenge.generator==Data([5]),
              challenge.options==supportedOptions,
              challenge.salt.count==32, challenge.serverPublic.count==512,
              peer>1, peer<n, (1...1_000_000).contains(challenge.iterations),
              password.utf8.count<=1024 else { throw Failure.invalidParameters }
        var random=[UInt8](repeating:0,count:32)
        let exponent:BigUInt
        if let privateExponent {
            guard privateExponent.count==32 else { throw Failure.invalidParameters }
            exponent=BigUInt(privateExponent)
        } else {
            guard SecRandomCopyBytes(kSecRandomDefault,random.count,&random)==errSecSuccess else { throw Failure.randomFailed }
            exponent=BigUInt(Data(random))
        }
        guard exponent>1 else { throw Failure.invalidParameters }
        let pass=Data(password.utf8)
        var derived=[UInt8](repeating:0,count:128)
        let status=pass.withUnsafeBytes { passwordBytes in
            challenge.salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.baseAddress?.assumingMemoryBound(to:CChar.self),pass.count,
                    saltBytes.baseAddress?.assumingMemoryBound(to:UInt8.self),challenge.salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),UInt32(challenge.iterations),&derived,derived.count)
            }
        }
        guard status==kCCSuccess else { throw Failure.derivationFailed }
        let x=BigUInt(hash(challenge.salt+hash(Data([58])+Data(derived))))
        let a=pad(g.power(exponent,modulus:n))
        let k=BigUInt(hash(group+pad(g))), u=BigUInt(hash(a+challenge.serverPublic))
        guard u>0 else { throw Failure.invalidParameters }
        let product=(k*g.power(x,modulus:n)) % n
        let base=(peer+n-product) % n
        guard base>1 else { throw Failure.invalidParameters }
        let secret=base.power(exponent+u*x,modulus:n)
        let key=hash(pad(secret))
        let generatorToken = tokenPadding == .groupWidth ? pad(g) : Data([5])
        let mixed=Data(zip(hash(group),hash(generatorToken)).map { $0 ^ $1 })
        var proofInput=mixed+hash(Data())+challenge.salt
        proofInput.append(a); proofInput.append(challenge.serverPublic); proofInput.append(key)
        let m1=hash(proofInput)
        return Proof(clientPublic:a,clientProof:m1,expectedServerProof:hash(a+m1+key),
            pendingWrapKey:Data(SHA256.hash(data:key).prefix(16)))
    }
    private static func hash(_ data:Data)->Data { Data(SHA512.hash(data:data)) }
    private static func pad(_ value:BigUInt)->Data { ARDAuthCrypto.padded(value,length:512) }
}
