import Foundation

/// Persistable connection parameters. Secrets and host-key approval are separate.
public struct SSHConfiguration: Codable, Equatable, Sendable {
    public enum Authentication: String, Codable, Sendable { case password, ed25519 }
    public enum ValidationError: Error { case invalidEndpoint }
    public let host: String
    public let port: UInt16
    public let username: String
    public let authentication: Authentication
    public let destinationHost: String

    public init(host: String, port: UInt16 = 22, username: String,
                authentication: Authentication = .password, destinationHost: String = "127.0.0.1") throws {
        guard Self.validHost(host), port > 0, Self.validHost(destinationHost),
              !username.isEmpty, username.utf8.count <= 255,
              username.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }) else {
            throw ValidationError.invalidEndpoint
        }
        self.host = host; self.port = port; self.username = username
        self.authentication = authentication; self.destinationHost = destinationHost
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(host: values.decode(String.self, forKey: .host),
                      port: values.decode(UInt16.self, forKey: .port),
                      username: values.decode(String.self, forKey: .username),
                      authentication: values.decode(Authentication.self, forKey: .authentication),
                      destinationHost: values.decode(String.self, forKey: .destinationHost))
    }

    private static func validHost(_ host: String) -> Bool {
        !host.isEmpty && host.utf8.count <= 253 &&
        !host.contains(where: { $0.isWhitespace || $0 == "/" || $0 == "@" || $0 == "\0" || $0 == "[" || $0 == "]" })
    }
}
