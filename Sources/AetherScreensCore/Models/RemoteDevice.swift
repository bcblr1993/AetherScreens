import Foundation
import AetherScreensSSH

/// App-level representation of a remote computer configured for screen sharing.
public struct RemoteDevice: Codable, Identifiable, Equatable, Sendable {
    public enum DeviceType: String, Codable, CaseIterable, Sendable {
        case mac = "macOS"
        case windows = "Windows"
        case linux = "Linux"
        case other = "Other"

        public var systemIcon: String {
            switch self {
            case .mac: return "apple.logo"
            case .windows: return "window.casement"
            case .linux: return "terminal.fill"
            case .other: return "desktopcomputer"
            }
        }
    }

    public enum AuthMethod: String, Codable, CaseIterable, Sendable {
        case vncPassword = "VNC Password"
        case macAccount = "macOS Account"
        case none = "None"
    }

    public let id: UUID
    public var name: String
    public var host: String
    public var port: UInt16
    public var deviceType: DeviceType
    public var authMethod: AuthMethod
    public var username: String?
    public var isOnline: Bool
    public var lastConnected: Date?
    public var isTailscaleNode: Bool
    public var macAddress: String?
    public var disconnectAction: RemoteDisconnectAction?
    public var cursorSpeed: Double?
    public var sharedClipboard: Bool?
    public var imageCompression: RemoteImageCompressionPolicy?
    /// Server screen ID; nil means the complete desktop. Wire ID zero is valid.
    public var preferredDisplayID: UInt32?
    public var sshConfiguration: SSHConfiguration?
    public var effectiveSharedClipboard: Bool { sharedClipboard ?? true }
    /// Preserve the full resolution of connections saved by earlier versions.
    public var effectiveImageCompression: RemoteImageCompressionPolicy { imageCompression ?? .never }
    public static func validatedCursorSpeed(_ value: Double) -> Double {
        value.isFinite ? min(2, max(0.25, value)) : 1
    }
    public var effectiveCursorSpeed: Double { Self.validatedCursorSpeed(cursorSpeed ?? 1) }

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: UInt16 = RFBConstants.defaultPort,
        deviceType: DeviceType = .mac,
        authMethod: AuthMethod = .vncPassword,
        username: String? = nil,
        isOnline: Bool = true,
        lastConnected: Date? = nil,
        isTailscaleNode: Bool = false,
        macAddress: String? = nil,
        disconnectAction: RemoteDisconnectAction? = nil,
        cursorSpeed: Double? = nil,
        sharedClipboard: Bool? = nil,
        imageCompression: RemoteImageCompressionPolicy? = nil,
        preferredDisplayID: UInt32? = nil,
        sshConfiguration: SSHConfiguration? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.deviceType = deviceType
        self.authMethod = authMethod
        self.username = username
        self.isOnline = isOnline
        self.lastConnected = lastConnected
        self.isTailscaleNode = isTailscaleNode
        self.macAddress = macAddress
        self.disconnectAction = disconnectAction
        self.cursorSpeed = cursorSpeed
        self.sharedClipboard = sharedClipboard
        self.imageCompression = imageCompression
        self.preferredDisplayID = preferredDisplayID
        self.sshConfiguration = sshConfiguration
    }

    /// Creates a RemoteDevice from a Tailscale node
    public static func fromTailscaleDevice(_ ts: TailscaleDevice) -> RemoteDevice? {
        guard let ip = ts.tailscaleIPv4 else { return nil }
        let type: DeviceType = ts.isMac ? .mac : .other

        return RemoteDevice(
            name: ts.displayName,
            host: ip,
            port: RFBConstants.defaultPort,
            deviceType: type,
            authMethod: .vncPassword,
            isOnline: ts.isOnline,
            isTailscaleNode: true
        )
    }
}
