import Foundation
import Security

/// Type33 packet-2 encoder. Reference-derived framing awaits live acceptance;
/// no speculative trailing bytes are appended to the bounded meaningful body.
enum AppleSRPProofPacket {
    enum Failure: Error { case invalidFields, randomFailed }

    static func encode(clientPublic: Data, clientProof: Data, options: String,
                       clientRandom: Data? = nil) throws -> Data {
        guard clientPublic.count == 512, clientProof.count == 64,
              options == AppleSRP6aProof.supportedOptions else { throw Failure.invalidFields }
        let random: Data
        if let clientRandom {
            guard clientRandom.count == 16 else { throw Failure.invalidFields }
            random = clientRandom
        } else {
            var bytes = [UInt8](repeating: 0, count: 16)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess
            else { throw Failure.randomFailed }
            random = Data(bytes)
        }
        var inner = Data()
        append(clientPublic.count, width: 2, to: &inner); inner.append(clientPublic)
        append(clientProof.count, width: 1, to: &inner); inner.append(clientProof)
        let text = Data(options.utf8)
        append(text.count, width: 2, to: &inner); inner.append(text)
        append(random.count, width: 1, to: &inner); inner.append(random)
        var packet = Data()
        append(14 + inner.count, width: 4, to: &packet)
        packet.append(contentsOf: [1, 0, 82, 83, 65, 49, 0, 2])
        append(inner.count + 4, width: 2, to: &packet)
        append(0, width: 2, to: &packet)
        append(inner.count, width: 2, to: &packet)
        packet.append(inner)
        return packet
    }

    private static func append(_ value: Int, width: Int, to data: inout Data) {
        for shift in stride(from: (width - 1) * 8, through: 0, by: -8) {
            data.append(UInt8(truncatingIfNeeded: value >> shift))
        }
    }
}
