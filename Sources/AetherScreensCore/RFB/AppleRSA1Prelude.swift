import Foundation

/// Credential-free type-33 key discovery. This validates the envelope only;
/// callers still need RSA key validation/trust and authenticated SRP proofs.
enum AppleRSA1Prelude {
    enum Failure: Error { case invalidEnvelope }
    static let maximumResponseBytes = 8192
    // Selector is sent separately. Length excludes its own u32 prefix.
    static let publicKeyRequest = Data([0, 0, 0, 10, 1, 0, 82, 83, 65, 49, 0, 0, 0, 0])

    static func extractSubjectPublicKeyInfo(_ frame: Data) throws -> Data {
        guard frame.count >= 11, frame.count <= maximumResponseBytes + 4 else {
            throw Failure.invalidEnvelope
        }
        let bytes = Array(frame)
        let length = bytes.prefix(4).reduce(0) { $0 << 8 | Int($1) }
        // The response version is little-endian, unlike all length fields.
        guard length == bytes.count - 4,
              bytes[4...7].elementsEqual([0, 1, 0, 0]) else {
            throw Failure.invalidEnvelope
        }
        let derLength = Int(bytes[8]) << 8 | Int(bytes[9])
        guard derLength > 0, length == derLength + 7,
              bytes[10] == 0x30, bytes.last == 0 else {
            throw Failure.invalidEnvelope
        }
        return Data(bytes[10..<(10 + derLength)])
    }
}
