import Foundation

/// Experimental server-driven framebuffer subscription for the native record profile.
enum AppleFramebufferControl {
    static func arm(width: Int, height: Int, selectedScreen: UInt32 = 0) -> Data? {
        guard (1...Int(UInt16.max)).contains(width), (1...Int(UInt16.max)).contains(height) else { return nil }
        // This profile configures one display. Subscribe explicitly to its first
        // screen: the all/main sentinel stalls after reconfiguration on the QA
        // Mac, whereas screen 0 sustains measured pixel changes. The diagnostic
        // flag indicates screen selection, not subscription success.
        var bytes = Data([9, 0, 0, 1])
        var screen = selectedScreen.bigEndian
        withUnsafeBytes(of: &screen) { bytes.append(contentsOf: $0) }
        bytes.append(contentsOf: [0, 0, 0, 0])
        for value in [width, height] {
            var word = UInt16(value).bigEndian
            withUnsafeBytes(of: &word) { bytes.append(contentsOf: $0) }
        }
        return bytes
    }
}
