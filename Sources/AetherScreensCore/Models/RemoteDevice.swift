import Foundation

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

    public enum RemoteProtocol: String, Codable, CaseIterable, Sendable {
        case rfb = "RFB"
        case rdp = "RDP"

        public var defaultPort: UInt16 {
            switch self {
            case .rfb: return 5900
            case .rdp: return 3389
            }
        }
    }

    public enum AuthMethod: String, Codable, CaseIterable, Sendable {
        case vncPassword = "VNC Password"
        case macAccount = "macOS Account"
        case windowsCredentials = "Windows Credentials"
        case none = "None"
    }

    public let id: UUID
    public var name: String
    public var host: String
    public var port: UInt16
    public var deviceType: DeviceType
    public var remoteProtocol: RemoteProtocol
    public var authMethod: AuthMethod
    public var username: String?
    public var isOnline: Bool
    public var lastConnected: Date?
    public var isTailscaleNode: Bool
    public var macAddress: String?
    public var ssh: SSHConnectionSettings?
    public var isFavorite: Bool
    public var tags: [String]
    public var desktopWidth: Int?
    public var desktopHeight: Int?

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: UInt16 = RFBConstants.defaultPort,
        deviceType: DeviceType = .mac,
        remoteProtocol: RemoteProtocol? = nil,
        authMethod: AuthMethod = .vncPassword,
        username: String? = nil,
        isOnline: Bool = true,
        lastConnected: Date? = nil,
        isTailscaleNode: Bool = false,
        macAddress: String? = nil,
        ssh: SSHConnectionSettings? = nil,
        isFavorite: Bool = false,
        tags: [String] = [],
        desktopWidth: Int? = nil,
        desktopHeight: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.deviceType = deviceType
        self.remoteProtocol = remoteProtocol ?? (port == 3389 ? .rdp : .rfb)
        self.authMethod = authMethod
        self.username = username
        self.isOnline = isOnline
        self.lastConnected = lastConnected
        self.isTailscaleNode = isTailscaleNode
        self.macAddress = macAddress
        self.ssh = ssh
        self.isFavorite = isFavorite
        self.tags = tags
        self.desktopWidth = desktopWidth
        self.desktopHeight = desktopHeight
    }

    enum CodingKeys: String, CodingKey {
        case id, name, host, port, deviceType, remoteProtocol, authMethod, username, isOnline, lastConnected, isTailscaleNode, macAddress, ssh, isFavorite, tags, desktopWidth, desktopHeight
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.host = try container.decode(String.self, forKey: .host)
        let portValue = try container.decode(UInt16.self, forKey: .port)
        self.port = portValue
        self.deviceType = try container.decode(DeviceType.self, forKey: .deviceType)
        let proto = try container.decodeIfPresent(RemoteProtocol.self, forKey: .remoteProtocol)
        self.remoteProtocol = proto ?? (portValue == 3389 ? .rdp : .rfb)
        self.authMethod = try container.decodeIfPresent(AuthMethod.self, forKey: .authMethod) ?? .vncPassword
        self.username = try container.decodeIfPresent(String.self, forKey: .username)
        self.isOnline = try container.decode(Bool.self, forKey: .isOnline)
        self.lastConnected = try container.decodeIfPresent(Date.self, forKey: .lastConnected)
        self.isTailscaleNode = try container.decode(Bool.self, forKey: .isTailscaleNode)
        self.macAddress = try container.decodeIfPresent(String.self, forKey: .macAddress)
        self.ssh = try container.decodeIfPresent(SSHConnectionSettings.self, forKey: .ssh)
        self.isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.desktopWidth = try container.decodeIfPresent(Int.self, forKey: .desktopWidth)
        self.desktopHeight = try container.decodeIfPresent(Int.self, forKey: .desktopHeight)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(deviceType, forKey: .deviceType)
        try container.encode(remoteProtocol, forKey: .remoteProtocol)
        try container.encode(authMethod, forKey: .authMethod)
        try container.encodeIfPresent(username, forKey: .username)
        try container.encode(isOnline, forKey: .isOnline)
        try container.encodeIfPresent(lastConnected, forKey: .lastConnected)
        try container.encode(isTailscaleNode, forKey: .isTailscaleNode)
        try container.encodeIfPresent(macAddress, forKey: .macAddress)
        try container.encodeIfPresent(ssh, forKey: .ssh)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(desktopWidth, forKey: .desktopWidth)
        try container.encodeIfPresent(desktopHeight, forKey: .desktopHeight)
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
