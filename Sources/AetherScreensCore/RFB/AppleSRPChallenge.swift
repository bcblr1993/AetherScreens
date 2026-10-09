import Foundation

/// Bounded decoding only. The SRP engine must still validate its trusted group,
/// negotiated algorithms and server proof before accepting authentication.
struct AppleSRPChallenge: Sendable {
    enum Failure: Error { case invalidFrame, invalidField, excessiveCost }
    static let maximumFrameBytes = 8192
    let step: UInt32
    let modulus: Data
    let generator: Data
    let salt: Data
    let serverPublic: Data
    let iterations: UInt64
    let options: String

    init(frame: Data, maximumIterations: UInt64 = 1_000_000) throws {
        guard (15...Self.maximumFrameBytes).contains(frame.count) else { throw Failure.invalidFrame }
        var reader = Reader(frame)
        let total = try reader.integer(4)
        // Actual macOS 27 response: u32 stage, u16 nested length, u32 payload.
        // This differs from the reference memo's outer-envelope description.
        step = UInt32(try reader.integer(4))
        let nested = try reader.integer(2), payload = try reader.integer(4)
        guard total == frame.count - 4, payload == frame.count - 14,
              nested == payload + 4, step == 2 else { throw Failure.invalidFrame }
        guard try reader.integer(1) == 0 else { throw Failure.invalidField }
        modulus = try reader.atom(prefix:2, maximum:512)
        generator = try reader.atom(prefix:2, maximum:64)
        salt = try reader.atom(prefix:1, maximum:255)
        serverPublic = try reader.atom(prefix:2, maximum:512)
        iterations = try reader.integer(8)
        let text = try reader.atom(prefix:2, maximum:1024)
        guard reader.finished, (16...512).contains(modulus.count),
              serverPublic.count == modulus.count, !generator.isEmpty, !salt.isEmpty,
              let options = String(data:text,encoding:.utf8), !options.isEmpty,
              !options.contains("\0") else { throw Failure.invalidField }
        guard iterations > 0, iterations <= maximumIterations else { throw Failure.excessiveCost }
        self.options = options
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0
        init(_ data: Data) { bytes = Array(data) }
        var finished: Bool { offset == bytes.count }
        mutating func integer(_ count: Int) throws -> UInt64 {
            guard count <= bytes.count - offset else { throw Failure.invalidFrame }
            var value: UInt64 = 0
            for _ in 0..<count { value = value << 8 | UInt64(bytes[offset]); offset += 1 }
            return value
        }
        mutating func atom(prefix:Int, maximum:Int) throws -> Data {
            let length = try integer(prefix)
            guard length <= maximum, length <= bytes.count - offset else { throw Failure.invalidField }
            let end = offset + Int(length)
            let data = Data(bytes[offset..<end]); offset = end
            return data
        }
    }
}
