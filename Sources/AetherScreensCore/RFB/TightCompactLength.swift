import Foundation

/// Tight's length prefix uses seven bits in the first two bytes and all eight
/// bits in the third byte. The caller retains incomplete input until more arrives.
enum TightCompactLength {
    static let maximum = 4_194_303

    static func parse(_ data: Data) -> (value: Int, bytesConsumed: Int)? {
        var value = 0
        for (offset, byte) in data.prefix(3).enumerated() {
            if offset == 2 {
                return (value | (Int(byte) << 14), 3)
            }
            value |= Int(byte & 0x7f) << (offset * 7)
            if byte & 0x80 == 0 { return (value, offset + 1) }
        }
        return nil
    }
}
