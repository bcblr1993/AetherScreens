import Foundation

/// Explicit user-selected actions; a lost connection must never execute these.
public enum DisconnectAction: String, Codable, CaseIterable, Sendable, Identifiable {
    case none, lockScreen, logOut, controlAltDelete
    case topLeft, topRight, bottomLeft, bottomRight
    public var id: String { rawValue }
    public var titleKey: String {
        switch self {
        case .none: return "No Action"
        case .lockScreen: return "Lock Screen"
        case .logOut: return "Log Out Remote User"
        case .controlAltDelete: return "Send Ctrl-Alt-Delete"
        case .topLeft: return "Top Left Hot Corner"
        case .topRight: return "Top Right Hot Corner"
        case .bottomLeft: return "Bottom Left Hot Corner"
        case .bottomRight: return "Bottom Right Hot Corner"
        }
    }
    public func isSupported(on type: RemoteDevice.DeviceType) -> Bool {
        switch self {
        case .none: return true
        case .controlAltDelete: return type == .windows || type == .linux
        default: return type == .mac
        }
    }

    func encodedPacket(type: RemoteDevice.DeviceType, width: Int, height: Int) -> Data {
        guard isSupported(on: type) else { return Data() }
        let keys: [UInt32]
        switch self {
        case .none: return Data()
        case .lockScreen:
            return MacKeyMap.MacShortcut.lockScreen.keySequence.reduce(into: Data()) {
                $0.append(RFBEncoder.encodeKeyEvent(down: $1.down, keySym: $1.key))
            }
        case .logOut: keys = [MacKeyMap.optionLeft, MacKeyMap.shiftLeft, MacKeyMap.commandLeft, 113]
        case .controlAltDelete: keys = [MacKeyMap.controlLeft, MacKeyMap.optionLeft, MacKeyMap.delete]
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            guard width > 0, height > 0 else { return Data() }
            let right = UInt16(clamping: width - 1), bottom = UInt16(clamping: height - 1)
            let x: UInt16 = self == .topRight || self == .bottomRight ? right : 0
            let y: UInt16 = self == .bottomLeft || self == .bottomRight ? bottom : 0
            var packet = RFBEncoder.encodePointerEvent(buttonMask: [], x: right / 2, y: bottom / 2)
            packet.append(RFBEncoder.encodePointerEvent(buttonMask: [], x: x, y: y))
            return packet
        }
        var packet = Data()
        for key in keys { packet.append(RFBEncoder.encodeKeyEvent(down: true, keySym: key)) }
        for key in keys.reversed() { packet.append(RFBEncoder.encodeKeyEvent(down: false, keySym: key)) }
        return packet
    }
}

/// Preferences are scoped to a saved computer and contain no credentials.
public final class DisconnectActionStore: @unchecked Sendable {
    public static let shared = DisconnectActionStore()
    private let defaults: UserDefaults
    private let prefix = "aetherscreens.disconnect-action."
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load(for id: UUID, type: RemoteDevice.DeviceType) -> DisconnectAction {
        guard let value = defaults.string(forKey: prefix + id.uuidString),
              let action = DisconnectAction(rawValue: value), action.isSupported(on: type) else { return .none }
        return action
    }
    public func save(_ action: DisconnectAction, for id: UUID) {
        defaults.set(action.rawValue, forKey: prefix + id.uuidString)
    }
    public func remove(for id: UUID) { defaults.removeObject(forKey: prefix + id.uuidString) }
}
