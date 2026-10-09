import Foundation

/// Strict final-proof grammar validated against the authorized Mac mini:
/// 98-byte body, stage 2. Keep the expected stage explicit for other profiles.
/// Parsing alone never verifies M2 or accepts an RFB SecurityResult.
struct AppleSRPServerProof: Sendable {
    enum Failure: Error { case invalidFrame }
    let proof: Data
    let random: Data

    init(frame: Data, expectedStep: UInt32) throws {
        // Fixed profile: 14-byte envelope plus %o M2(64), %o random(16),
        // %s empty and %u zero. Validate before copying attacker input.
        guard frame.count == 102 else { throw Failure.invalidFrame }
        let bytes = Array(frame)
        func integer(_ offset: Int, _ width: Int) -> UInt32 {
            bytes[offset..<(offset + width)].reduce(0) { ($0 << 8) | UInt32($1) }
        }
        guard integer(0, 4) == 98, integer(4, 4) == expectedStep,
              integer(8, 2) == 92, integer(10, 4) == 88,
              bytes[14] == 64, bytes[79] == 16,
              integer(96, 2) == 0, integer(98, 4) == 0
        else { throw Failure.invalidFrame }
        proof = Data(bytes[15..<79])
        random = Data(bytes[80..<96])
    }
}
