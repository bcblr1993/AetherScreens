import Foundation
import CryptoKit
import CommonCrypto

/// Experimental Apple control-record codec. Confine an instance to one transport queue.
/// Not enabled by the standard RFB client; actual Apple bootstrap remains a separate gate.
final class AppleRFBRecordLayer {
    enum Failure: Error, Equatable { case invalidKey, rekeyRequired, invalidRecord, integrity, cipher, sequenceExhausted, closed, bodyTooLarge }
    static let maximumBodySize = 65_498
    private var wrapKey: [UInt8]
    private var key: [UInt8]?
    private var sendIV: [UInt8] = []
    private var receiveIV: [UInt8] = []
    private(set) var sendSequence: UInt64 = 0
    private(set) var receiveSequence: UInt64 = 0
    private var closed = false

    init(wrapKey: Data) throws {
        guard wrapKey.count == 16 else { throw Failure.invalidKey }
        self.wrapKey = Array(wrapKey)
    }

    /// The two ECB-wrapped blocks install independent send/receive CBC streams.
    /// A later rekey rotates the wrap key and IVs, preserving record sequences.
    @discardableResult
    func installRekey(_ payload: Data) throws -> UInt32 {
        guard !closed else { throw Failure.closed }
        do {
            guard payload.count == 36 else { throw Failure.invalidRecord }
            let bytes = Array(payload)
            let generation = bytes.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            let unwrapped = try Self.crypt(Array(bytes.dropFirst(4)), key: wrapKey,
                                           iv: [], encrypt: false, ecb: true)
            key = Array(unwrapped.prefix(16))
            wrapKey = Array(unwrapped.prefix(16))
            sendIV = Array(unwrapped.suffix(16))
            receiveIV = sendIV
            return generation
        } catch {
            close()
            throw error
        }
    }

    func seal(_ body: Data) throws -> Data {
        guard !closed else { throw Failure.closed }
        guard let key else { throw Failure.rekeyRequired }
        guard body.count <= Self.maximumBodySize else { throw Failure.bodyTooLarge }
        do {
            guard sendSequence <= UInt32.max else { throw Failure.sequenceExhausted }
            var plaintext = [UInt8(truncatingIfNeeded: body.count >> 8), UInt8(truncatingIfNeeded: body.count)]
            plaintext.append(contentsOf: body)
            let filler = (16 - (plaintext.count + 20) % 16) % 16
            plaintext.append(contentsOf: repeatElement(0, count: filler))
            plaintext.append(contentsOf: Self.digest(sequence: UInt32(sendSequence), bytes: plaintext))
            let ciphertext = try Self.crypt(plaintext, key: key, iv: sendIV, encrypt: true)
            sendIV = Array(ciphertext.suffix(16))
            sendSequence += 1
            return Data([UInt8(truncatingIfNeeded: ciphertext.count >> 8), UInt8(truncatingIfNeeded: ciphertext.count)]) + Data(ciphertext)
        } catch {
            close()
            throw error
        }
    }

    /// Accept exactly one outer record. Fragment reassembly belongs to the transport.
    /// Any receive failure closes the codec; corrupted/replayed records cannot be retried.
    func open(_ packet: Data) throws -> Data {
        guard !closed else { throw Failure.closed }
        guard let key else { throw Failure.rekeyRequired }
        do {
            guard receiveSequence <= UInt32.max else { throw Failure.sequenceExhausted }
            guard (34...65_522).contains(packet.count) else { throw Failure.invalidRecord }
            let bytes = Array(packet)
            let count = Int(bytes[0]) << 8 | Int(bytes[1])
            guard count >= 32, count % 16 == 0, bytes.count == count + 2 else { throw Failure.invalidRecord }
            let ciphertext = Array(bytes.dropFirst(2))
            let plaintext = try Self.crypt(ciphertext, key: key, iv: receiveIV, encrypt: false)
            let authenticatedCount = plaintext.count - 20
            let expected = Self.digest(sequence: UInt32(receiveSequence), bytes: Array(plaintext.prefix(authenticatedCount)))
            let actual = plaintext.suffix(20)
            var difference: UInt8 = 0
            for (a, b) in zip(expected, actual) { difference |= a ^ b }
            guard difference == 0 else { throw Failure.integrity }
            let bodyCount = Int(plaintext[0]) << 8 | Int(plaintext[1])
            let fillerCount = authenticatedCount - 2 - bodyCount
            guard bodyCount <= Self.maximumBodySize, (0..<16).contains(fillerCount) else { throw Failure.invalidRecord }
            receiveIV = Array(ciphertext.suffix(16))
            receiveSequence += 1
            return Data(plaintext[2..<(2 + bodyCount)])
        } catch {
            close()
            throw error
        }
    }

    func close() {
        closed = true
        key = nil
        wrapKey.removeAll()
        sendIV.removeAll()
        receiveIV.removeAll()
    }

    private static func digest(sequence: UInt32, bytes: [UInt8]) -> [UInt8] {
        var hash = Insecure.SHA1()
        hash.update(data: Data([UInt8(truncatingIfNeeded: sequence >> 24), UInt8(truncatingIfNeeded: sequence >> 16),
                                UInt8(truncatingIfNeeded: sequence >> 8), UInt8(truncatingIfNeeded: sequence)]))
        hash.update(data: Data(bytes))
        return Array(hash.finalize())
    }

    private static func crypt(_ input: [UInt8], key: [UInt8], iv: [UInt8], encrypt: Bool, ecb: Bool = false) throws -> [UInt8] {
        var output = [UInt8](repeating: 0, count: input.count)
        var written = 0
        let status = iv.withUnsafeBytes { ivBytes in
            CCCrypt(CCOperation(encrypt ? kCCEncrypt : kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                    CCOptions(ecb ? kCCOptionECBMode : 0), key, key.count, ecb ? nil : ivBytes.baseAddress,
                    input, input.count, &output, output.count, &written)
        }
        guard status == kCCSuccess, written == input.count else { throw Failure.cipher }
        return output
    }
}
