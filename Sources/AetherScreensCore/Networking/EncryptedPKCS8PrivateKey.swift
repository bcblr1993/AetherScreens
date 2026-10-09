import Foundation
import CommonCrypto

/// Bounded PKCS#8 PBES2 import. Call off the UI executor: PBKDF2 deliberately
/// consumes CPU. Plaintext is returned for the existing local Keychain/session
/// import path; neither the passphrase nor encrypted input is persisted here.
enum EncryptedPKCS8PrivateKey {
    enum Failure: Error, Equatable { case invalid, unsupported, decryptionFailed, tooExpensive }
    static let maximumIterations = 2_000_000

    static func decrypt(_ data: Data, passphrase: String) throws -> Data {
        guard data.count <= SSHPrivateKey.maximumSize else { throw SSHPrivateKey.Failure.tooLarge }
        guard passphrase.utf8.count <= 4096,
              let text = String(data: data, encoding: .utf8) else { throw Failure.invalid }
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.first == "-----BEGIN ENCRYPTED PRIVATE KEY-----",
              lines.last == "-----END ENCRYPTED PRIVATE KEY-----",
              let encoded = Data(base64Encoded: lines.dropFirst().dropLast().joined()) else { throw Failure.invalid }
        var root = DER(Array(encoded))
        var envelope = try root.sequence()
        try root.end()
        var algorithm = try envelope.sequence()
        guard try algorithm.value(0x06) == [0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x05,0x0d] else { throw Failure.unsupported }
        var parameters = try algorithm.sequence()
        try algorithm.end()
        var kdf = try parameters.sequence()
        guard try kdf.value(0x06) == [0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x05,0x0c] else { throw Failure.unsupported }
        var derivation = try kdf.sequence()
        try kdf.end()
        let salt = try derivation.value(0x04)
        guard (8...64).contains(salt.count) else { throw Failure.invalid }
        let iterations = try derivation.integer()
        guard iterations > 0 else { throw Failure.invalid }
        guard iterations <= maximumIterations else { throw Failure.tooExpensive }
        let explicitLength = derivation.tag == 0x02 ? try derivation.integer() : nil
        var prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1)
        if derivation.tag != nil {
            var identifier = try derivation.sequence()
            let oid = try identifier.value(0x06)
            switch oid {
            case [0x2a,0x86,0x48,0x86,0xf7,0x0d,0x02,0x07]: prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1)
            case [0x2a,0x86,0x48,0x86,0xf7,0x0d,0x02,0x09]: prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256)
            case [0x2a,0x86,0x48,0x86,0xf7,0x0d,0x02,0x0a]: prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA384)
            case [0x2a,0x86,0x48,0x86,0xf7,0x0d,0x02,0x0b]: prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512)
            default: throw Failure.unsupported
            }
            if identifier.tag != nil { guard try identifier.value(0x05).isEmpty else { throw Failure.invalid } }
            try identifier.end()
        }
        try derivation.end()
        var cipher = try parameters.sequence()
        let keyLength: Int
        switch try cipher.value(0x06) {
        case [0x60,0x86,0x48,0x01,0x65,0x03,0x04,0x01,0x02]: keyLength = 16
        case [0x60,0x86,0x48,0x01,0x65,0x03,0x04,0x01,0x16]: keyLength = 24
        case [0x60,0x86,0x48,0x01,0x65,0x03,0x04,0x01,0x2a]: keyLength = 32
        default: throw Failure.unsupported
        }
        guard explicitLength == nil || explicitLength == keyLength else { throw Failure.invalid }
        let iv = try cipher.value(0x04)
        guard iv.count == kCCBlockSizeAES128 else { throw Failure.invalid }
        try cipher.end(); try parameters.end()
        let ciphertext = try envelope.value(0x04)
        guard !ciphertext.isEmpty, ciphertext.count % kCCBlockSizeAES128 == 0 else { throw Failure.invalid }
        try envelope.end()

        var password = Array(passphrase.utf8CString)
        var key = [UInt8](repeating: 0, count: keyLength)
        var plaintext = [UInt8](repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
        defer {
            // Clear these owned work buffers; Swift String/Data copies are not
            // guaranteed to be zeroized and are not represented as such.
            _ = password.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }
            _ = key.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }
            _ = plaintext.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }
        }
        let derived = password.withUnsafeBufferPointer { password in
            salt.withUnsafeBufferPointer { salt in
                key.withUnsafeMutableBufferPointer { key in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password.baseAddress,
                        password.count - 1, salt.baseAddress, salt.count, prf,
                        UInt32(iterations), key.baseAddress, key.count)
                }
            }
        }
        guard derived == kCCSuccess else { throw Failure.decryptionFailed }
        var written = 0
        let decrypted = key.withUnsafeBufferPointer { key in
            iv.withUnsafeBufferPointer { iv in
                ciphertext.withUnsafeBufferPointer { input in
                    plaintext.withUnsafeMutableBufferPointer { output in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding), key.baseAddress, key.count,
                            iv.baseAddress, input.baseAddress, input.count,
                            output.baseAddress, output.count, &written)
                    }
                }
            }
        }
        guard decrypted == kCCSuccess, written > 0, written <= plaintext.count else { throw Failure.decryptionFailed }
        // Distinguish a decrypted, unsupported key algorithm from a bad secret.
        do {
            var decoded = DER(Array(plaintext.prefix(written)))
            var info = try decoded.sequence()
            try decoded.end()
            guard try info.integer() == 0 else { throw Failure.unsupported }
            var identifier = try info.sequence()
            guard try identifier.value(0x06) == [0x2a,0x86,0x48,0xce,0x3d,0x02,0x01] else { throw Failure.unsupported }
            let curve = try identifier.value(0x06)
            guard [[0x2a,0x86,0x48,0xce,0x3d,0x03,0x01,0x07], [0x2b,0x81,0x04,0x00,0x22], [0x2b,0x81,0x04,0x00,0x23]].contains(curve) else { throw Failure.unsupported }
            try identifier.end()
        } catch Failure.unsupported { throw Failure.unsupported }
        catch { throw Failure.decryptionFailed }
        let base64 = Data(plaintext.prefix(written)).base64EncodedString()
        var pem = "-----BEGIN PRIVATE KEY-----\n"
        var cursor = base64.startIndex
        while cursor != base64.endIndex {
            let end = base64.index(cursor, offsetBy: 64, limitedBy: base64.endIndex) ?? base64.endIndex
            pem += base64[cursor..<end] + "\n"
            cursor = end
        }
        pem += "-----END PRIVATE KEY-----\n"
        let normalized = Data(pem.utf8)
        guard normalized.count <= SSHPrivateKey.maximumSize else { throw Failure.invalid }
        do { _ = try SSHPrivateKey.decode(normalized) }
        catch { throw Failure.decryptionFailed }
        return normalized
    }

    private struct DER {
        let bytes: [UInt8]
        var offset = 0
        init(_ bytes: [UInt8]) { self.bytes = bytes }
        var tag: UInt8? { offset < bytes.count ? bytes[offset] : nil }
        mutating func end() throws { guard offset == bytes.count else { throw Failure.invalid } }
        mutating func sequence() throws -> DER { DER(try value(0x30)) }
        mutating func integer() throws -> Int {
            let bytes = try value(0x02)
            guard !bytes.isEmpty, bytes.count <= 4, bytes[0] & 0x80 == 0,
                  bytes.count == 1 || bytes[0] != 0 || bytes[1] & 0x80 != 0 else { throw Failure.invalid }
            return bytes.reduce(0) { ($0 << 8) | Int($1) }
        }
        mutating func value(_ expected: UInt8) throws -> [UInt8] {
            guard tag == expected, bytes.count - offset >= 2 else { throw Failure.invalid }
            offset += 1
            let first = bytes[offset]; offset += 1
            var length = Int(first)
            if first & 0x80 != 0 {
                let count = Int(first & 0x7f)
                guard (1...4).contains(count), bytes.count - offset >= count, bytes[offset] != 0 else { throw Failure.invalid }
                length = 0
                for _ in 0..<count { length = (length << 8) | Int(bytes[offset]); offset += 1 }
                guard length >= 128 else { throw Failure.invalid }
            }
            guard length <= bytes.count - offset else { throw Failure.invalid }
            let result = Array(bytes[offset..<offset + length]); offset += length
            return result
        }
    }
}
