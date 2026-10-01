import Foundation

/// Server-reported viewports within one RFB framebuffer. IDs and unknown flags are preserved.
public struct RFBDisplayLayout: Equatable, Sendable {
    public struct Screen: Equatable, Sendable {
        public let id: UInt32
        public let x: UInt16
        public let y: UInt16
        public let width: UInt16
        public let height: UInt16
        public let flags: UInt32
    }
    public let width: UInt16
    public let height: UInt16
    public let screens: [Screen]
}
