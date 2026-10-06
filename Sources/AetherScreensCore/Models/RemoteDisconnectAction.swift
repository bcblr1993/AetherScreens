import Foundation
import CoreGraphics

public enum RemoteDisconnectAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case disconnectOnly = "Disconnect Only"
    case lockScreen = "Lock Screen"
    case logOut = "Log Out Remote User"
    case topLeft = "Top Left", topRight = "Top Right"
    case bottomLeft = "Bottom Left", bottomRight = "Bottom Right"
    public var id: String { rawValue }

    // An unknown action from another app version must not discard the device list.
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .disconnectOnly
    }

    func inputPacket(width: Int, height: Int, display: CGRect?) -> Data {
        if self == .disconnectOnly { return Data() }
        let keys: [(key: UInt32, down: Bool)]
        if self == .lockScreen {
            keys = MacKeyMap.MacShortcut.lockScreen.keySequence
        } else if self == .logOut {
            // Use the system's immediate logout shortcut; the remote OS owns
            // application save handling and whether logout completes.
            keys = [(MacKeyMap.optionLeft, true), (MacKeyMap.shiftLeft, true), (MacKeyMap.commandLeft, true),
                    (113, true), (113, false), (MacKeyMap.commandLeft, false),
                    (MacKeyMap.shiftLeft, false), (MacKeyMap.optionLeft, false)]
        } else {
            let frame = CGRect(x: 0, y: 0, width: max(0, width), height: max(0, height))
            let bounds = (display ?? frame).intersection(frame)
            guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return Data() }
            let corner = CGPoint(x: self == .topRight || self == .bottomRight ? bounds.maxX - 1 : bounds.minX,
                                 y: self == .bottomLeft || self == .bottomRight ? bounds.maxY - 1 : bounds.minY)
            func packet(_ point: CGPoint) -> Data {
                let x = UInt16(min(CGFloat(UInt16.max), max(0, point.x)))
                let y = UInt16(min(CGFloat(UInt16.max), max(0, point.y)))
                return RFBEncoder.encodePointerEvent(buttonMask: [], x: x, y: y)
            }
            return packet(CGPoint(x: bounds.midX, y: bounds.midY)) + packet(corner)
        }
        return keys.reduce(into: Data()) { $0.append(RFBEncoder.encodeKeyEvent(down: $1.down, keySym: $1.key)) }
    }
}
