import Foundation

/// Native Apple bootstrap control packets, before outgoing record encryption.
/// These do not enable encryption in the ordinary RFB client by themselves.
enum AppleEncryptionControl {
    static let requestReceiveEncryption = Data([0x12, 0, 0, 1, 0, 1, 0, 1, 0, 0, 0, 1])
    static let enableSendEncryption = Data([0x12, 0, 0, 2, 0, 1, 0, 0])
    static let observe = Data([0x0a, 0, 0, 0])
    static let normalControl = Data([0x0a, 0, 0, 1])

    /// The initial cleartext framebuffer update contains exactly one rekey rect.
    /// Reject other framing before consuming a key payload or switching modes.
    static func isInitialRekey(updateHeader: Data, rectangleHeader: Data) -> Bool {
        updateHeader == Data([0, 0, 0, 1]) &&
        rectangleHeader == Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0x4f])
    }
}
