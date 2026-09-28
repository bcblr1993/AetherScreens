import Foundation

/// Represents a Tailscale node in the user's Tailnet.
public struct TailscaleDevice: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let hostname: String
    public let addresses: [String]
    public let os: String
    public let user: String?
    public let authorized: Bool?
    public let connectedToControl: Bool?
    public let lastSeen: String?

    public init(
        id: String,
        name: String,
        hostname: String,
        addresses: [String],
        os: String,
        user: String? = nil,
        authorized: Bool? = true,
        connectedToControl: Bool? = true,
        lastSeen: String? = nil
    ) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.addresses = addresses
        self.os = os
        self.user = user
        self.authorized = authorized
        self.connectedToControl = connectedToControl
        self.lastSeen = lastSeen
    }

    /// Extract the Tailscale IPv4 address (100.x.y.z)
    public var tailscaleIPv4: String? {
        return addresses.first { addr in
            addr.starts(with: "100.") && addr.contains(".")
        }
    }

    /// Whether this device is online according to Tailscale control plane
    public var isOnline: Bool {
        return connectedToControl ?? false
    }

    /// Whether this device is running macOS
    public var isMac: Bool {
        let osLower = os.lowercased()
        return osLower.contains("mac") || osLower.contains("darwin")
    }

    /// Clean display name for the device
    public var displayName: String {
        if !hostname.isEmpty {
            return hostname
        }
        // Extract prefix before first dot in FQDN
        return name.components(separatedBy: ".").first ?? name
    }
}

/// Tailscale API response envelope for listing devices
public struct TailscaleDevicesResponse: Codable, Sendable {
    public let devices: [TailscaleDevice]
}
