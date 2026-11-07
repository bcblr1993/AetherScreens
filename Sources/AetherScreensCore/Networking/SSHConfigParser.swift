import Foundation

/// Parses OpenSSH `~/.ssh/config` host blocks for quick SSH jump-host or computer import.
public enum SSHConfigParser {

    public struct HostEntry: Equatable, Identifiable, Sendable {
        public var id: String { alias }
        public let alias: String
        public var hostName: String
        public var user: String?
        public var port: UInt16
        public var identityFile: String?

        public init(
            alias: String,
            hostName: String,
            user: String? = nil,
            port: UInt16 = 22,
            identityFile: String? = nil
        ) {
            self.alias = alias
            self.hostName = hostName
            self.user = user
            self.port = port
            self.identityFile = identityFile
        }

        /// Convert into a validated `SSHConnectionSettings` jump-host configuration.
        public func toSSHConnectionSettings(defaultUsername: String = "root") -> SSHConnectionSettings? {
            guard let server = SSHServerAddress(host: hostName, port: port) else { return nil }
            let resolvedUser = (user?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? defaultUsername
            return SSHConnectionSettings(server: server, username: resolvedUser, authentication: .password)
        }
    }

    /// Parses the text contents of an OpenSSH config file, skipping wildcard patterns (`*`, `?`, `!`).
    public static func parse(_ content: String) -> [HostEntry] {
        var results: [HostEntry] = []
        var currentAliases: [String] = []
        var currentHostName: String?
        var currentUser: String?
        var currentPort: UInt16 = 22
        var currentIdentityFile: String?

        func flushCurrent() {
            for alias in currentAliases {
                guard !alias.isEmpty,
                      !alias.contains("*"),
                      !alias.contains("?"),
                      !alias.hasPrefix("!") else { continue }
                let resolvedHost = currentHostName ?? alias
                results.append(
                    HostEntry(
                        alias: alias,
                        hostName: resolvedHost,
                        user: currentUser,
                        port: currentPort,
                        identityFile: currentIdentityFile
                    )
                )
            }
            currentAliases = []
            currentHostName = nil
            currentUser = nil
            currentPort = 22
            currentIdentityFile = nil
        }

        for rawLine in content.components(separatedBy: .newlines) {
            let withoutComment = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? rawLine
            let trimmed = withoutComment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let parts: [String]
            if trimmed.contains("=") {
                parts = trimmed.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            } else {
                let tokens = trimmed.split(whereSeparator: { $0.isWhitespace })
                guard let key = tokens.first else { continue }
                let value = tokens.dropFirst().joined(separator: " ")
                parts = [String(key), value]
            }
            guard parts.count == 2, !parts[1].isEmpty else { continue }
            let key = parts[0].lowercased()
            let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))

            switch key {
            case "host":
                flushCurrent()
                currentAliases = value.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            case "hostname":
                if currentHostName == nil { currentHostName = value }
            case "user":
                if currentUser == nil { currentUser = value }
            case "port":
                if let p = UInt16(value), p > 0 { currentPort = p }
            case "identityfile":
                if currentIdentityFile == nil { currentIdentityFile = value }
            default:
                break
            }
        }
        flushCurrent()
        return results
    }
}
