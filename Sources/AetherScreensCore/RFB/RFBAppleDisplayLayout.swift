import Foundation
import CoreGraphics

/// Apple's physical display metadata. Record coordinates are signed global
/// edges; the framebuffer can contain all screens or just the acknowledged ID.
public struct RFBAppleDisplayLayout: Equatable, Sendable {
    public struct Screen: Equatable, Sendable {
        public let id: UInt32
        public let logicalBounds: CGRect
        public let backingBounds: CGRect
        public let nativeDensity: Double
        public let serverScale: Double
        public let flags: UInt32
        public let pixelFormat: RFBPixelFormat
        public var isMain: Bool { flags & 1 != 0 }
        public var isMirrored: Bool { flags & 2 != 0 }
    }
    public let logicalWidth: UInt16
    public let logicalHeight: UInt16
    public let width: UInt16
    public let height: UInt16
    public let selectedDisplayID: UInt32?
    public let sessionFlags: UInt32
    public let screens: [Screen]

    /// Console visibility/capability metadata does not change framebuffer pixels
    /// or pointer coordinates. Keep all display/scale/format changes distinct.
    func hasSameFramebufferLayout(as other: Self) -> Bool {
        logicalWidth == other.logicalWidth && logicalHeight == other.logicalHeight &&
            width == other.width && height == other.height &&
            selectedDisplayID == other.selectedDisplayID && screens == other.screens
    }

    /// Parse the body after its u16 byte length. Extra version-5 bytes are
    /// consumed by the transport and tolerated, as by Apple's viewer.
    public static func parse(_ payload: Data) -> Self? {
        let bytes = Array(payload)
        guard bytes.count >= 20, bytes.count <= 4096 else { return nil }
        func u16(_ offset: Int) -> UInt16 { UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1]) }
        func u32(_ offset: Int) -> UInt32 { bytes[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } }
        func number(_ offset: Int) -> Double {
            Double(bitPattern: bytes[offset..<(offset + 8)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) })
        }
        func rect(_ offset: Int) -> CGRect? {
            let edges = (0..<4).map { Int(Int16(bitPattern: u16(offset + $0 * 2))) }
            guard edges[2] > edges[0], edges[3] > edges[1] else { return nil }
            return CGRect(x: edges[1], y: edges[0], width: edges[3] - edges[1], height: edges[2] - edges[0])
        }
        let count = Int(u16(18)), width = u16(6), height = u16(8)
        guard u16(0) == 5, (1...25).contains(count), bytes.count >= 20 + count * 56,
              u16(2) > 0, u16(4) > 0, width > 0, height > 0,
              Int(width) * Int(height) <= 64_000_000 else { return nil }
        let selected = u32(10) == UInt32.max ? nil : u32(10)
        var screens: [Screen] = [], identifiers = Set<UInt32>()
        for index in 0..<count {
            let start = 20 + index * 56, id = u32(start + 16)
            guard id != UInt32.max, identifiers.insert(id).inserted else { return nil }
            guard let logical = rect(start + 20), let backing = rect(start + 28),
                  let pixelFormat = RFBPixelFormat.parse(from: Data(bytes[(start + 40)..<(start + 56)])) else { continue }
            let reportedScale = number(start + 8)
            let scale = reportedScale.isFinite && reportedScale > 0 && reportedScale <= 1 ? reportedScale : 1
            let reportedDensity = number(start)
            let density = reportedDensity == 0 ? backing.width / logical.width / scale : reportedDensity
            guard density.isFinite, (1...4).contains(density) else { continue }
            screens.append(.init(id: id, logicalBounds: logical, backingBounds: backing,
                                 nativeDensity: density, serverScale: scale, flags: u32(start + 36), pixelFormat: pixelFormat))
        }
        guard !screens.isEmpty, selected == nil || screens.contains(where: { $0.id == selected }) else { return nil }
        return Self(logicalWidth: u16(2), logicalHeight: u16(4), width: width, height: height,
                    selectedDisplayID: selected, sessionFlags: u32(14), screens: screens)
    }

    /// A selected physical framebuffer starts at zero, regardless of its global
    /// position. Combined frames normalize the signed backing union; gaps accept
    /// no new pointer position. Mouse coordinates undo the confirmed server scale.
    func serverCoordinates(x: UInt16, y: UInt16) -> (UInt16, UInt16)? {
        let point = CGPoint(x: min(Int(x), Int(width) - 1), y: min(Int(y), Int(height) - 1))
        let scale: Double
        if let selectedDisplayID, let screen = screens.first(where: { $0.id == selectedDisplayID }) {
            scale = screen.serverScale
        } else {
            let union = screens.reduce(CGRect.null) { $0.union($1.backingBounds) }
            guard screens.contains(where: { $0.backingBounds.offsetBy(dx: -union.minX, dy: -union.minY).contains(point) }) else { return nil }
            scale = screens[0].serverScale
            guard screens.allSatisfy({ abs($0.serverScale - scale) < 0.0001 }) else { return nil }
        }
        let remoteX = floor(point.x / scale), remoteY = floor(point.y / scale)
        guard remoteX.isFinite, remoteY.isFinite, remoteX <= CGFloat(UInt16.max), remoteY <= CGFloat(UInt16.max) else { return nil }
        return (UInt16(remoteX), UInt16(remoteY))
    }
}
