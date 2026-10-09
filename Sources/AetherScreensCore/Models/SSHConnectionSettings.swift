import Foundation
import Network

/// A validated SSH endpoint; the identity is independent of user accounts.
public struct SSHServerAddress: Codable, Equatable, Sendable {
    public let host: String
    public let port: UInt16

    public init?(host: String, port: UInt16 = 22) {
        let input = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        if input.hasPrefix("[") || input.hasSuffix("]") {
            guard input.hasPrefix("["), input.hasSuffix("]"),
                  IPv6Address(String(input.dropFirst().dropLast())) != nil else { return nil }
        }
        guard let request = ConnectionRequest(host: host, port: String(port)) else { return nil }
        self.host = request.device.host
        self.port = port
    }

    public var identity: String {
        let normalized: String
        if let address = IPv6Address(host) {
            normalized = "ipv6:" + address.rawValue.base64EncodedString()
        } else if let address = IPv4Address(host) {
            normalized = "ipv4:" + address.rawValue.base64EncodedString()
        } else {
            normalized = "dns:" + (host.hasSuffix(".") ? String(host.dropLast()) : host).lowercased()
        }
        return "[\(normalized)]:\(port)"
    }

    private enum CodingKeys: String, CodingKey { case host, port }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let host = try values.decode(String.self, forKey: .host)
        let port = try values.decode(UInt16.self, forKey: .port)
        guard let address = SSHServerAddress(host: host, port: port) else {
            throw DecodingError.dataCorruptedError(forKey: .host, in: values, debugDescription: "Invalid SSH endpoint")
        }
        self = address
    }
}

/// Secrets are referenced separately and never serialized into the device list.
public struct SSHConnectionSettings: Codable, Equatable, Sendable {
    public enum Authentication: Codable, Equatable, Sendable {
        case password
        case privateKey(UUID)
    }
    public let server: SSHServerAddress
    public let username: String
    public let authentication: Authentication
    public let remoteHost: String

    public init?(server: SSHServerAddress, username: String, authentication: Authentication = .password,
                 remoteHost: String = "127.0.0.1") {
        let account = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty, !account.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let target = SSHServerAddress(host: remoteHost) else { return nil }
        self.server = server
        self.username = account
        self.authentication = authentication
        self.remoteHost = target.host
    }

    private enum CodingKeys: String, CodingKey { case server, username, authentication, remoteHost }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let server = try values.decode(SSHServerAddress.self, forKey: .server)
        let username = try values.decode(String.self, forKey: .username)
        let authentication = try values.decode(Authentication.self, forKey: .authentication)
        let remoteHost = try values.decode(String.self, forKey: .remoteHost)
        guard let settings = SSHConnectionSettings(server: server, username: username,
            authentication: authentication, remoteHost: remoteHost) else {
            throw DecodingError.dataCorruptedError(forKey: .username, in: values, debugDescription: "Invalid SSH settings")
        }
        self = settings
    }
}
