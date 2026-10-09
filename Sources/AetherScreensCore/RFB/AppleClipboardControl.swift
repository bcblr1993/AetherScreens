import Foundation

/// Experimental Apple control messages, independent of record encryption.
enum AppleClipboardControl {
    static func request(promiseOnly: Bool = false) -> Data {
        var packet = Data(repeating: 0, count: 8)
        packet[0] = 0x0b
        packet[1] = promiseOnly ? 1 : 0
        return packet
    }

    static func monitoring(_ enabled: Bool) -> Data {
        var packet = Data(repeating: 0, count: 8)
        packet[0] = 0x15
        packet[3] = enabled ? 1 : 2
        return packet
    }
}
