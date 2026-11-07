import Foundation

/// Connection links are decoded in memory. Never log a URL: it may contain credentials.
public struct ConnectionLink {
    public enum Target { case saved(UUID), savedName(String), temporary(ConnectionRequest) }
    public let target: Target
    public let observeOnly: Bool?
    private let username: String?
    private let password: String?

    public enum Failure: Error, Equatable {
        case invalid, unsupportedOption, missingSavedComputer, ambiguousSavedComputer
        public var messageKey: String {
            switch self {
            case .invalid: return "This connection link is invalid."
            case .unsupportedOption: return "This connection link uses an unsupported option."
            case .missingSavedComputer: return "The computer in this link is not in your library."
            case .ambiguousSavedComputer: return "Several computers match this link. Use a link copied from the computer's menu."
            }
        }
    }

    public init(url: URL) throws {
        guard url.absoluteString.utf8.count <= 8192,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.fragment == nil,
              let scheme = components.scheme?.lowercased(), ["aetherscreens", "screens", "vnc", "rdp"].contains(scheme) else { throw Failure.invalid }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard query[item.name] == nil, let value = item.value,
                  !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { throw Failure.invalid }
            query[item.name] = value
        }
        let hostLower = components.host?.lowercased()
        let isActionRoute = (scheme == "aetherscreens") || (scheme == "screens" && (hostLower == "connect" || hostLower == "saved"))
        let allowed: Set<String> = !isActionRoute
            ? ["observe"]
            : ["host", "port", "name", "username", "password", "observe", "protocol", "sshHost", "sshPort", "sshUser"]
        guard Set(query.keys).isSubset(of: allowed) else { throw Failure.unsupportedOption }
        if let value = query["observe"] {
            guard ["true", "false"].contains(value) else { throw Failure.invalid }
            observeOnly = value == "true"
        } else { observeOnly = nil }
        // URLComponents has already decoded these once. Literal percent escapes
        // inside an account/password must survive a round trip unchanged.
        let urlUsername = components.user
        let urlPassword = components.password
        guard !(urlUsername != nil && query["username"] != nil), !(urlPassword != nil && query["password"] != nil) else { throw Failure.invalid }
        username = query["username"] ?? urlUsername
        password = query["password"] ?? urlPassword
        for value in [username, password, query["sshHost"], query["sshUser"]].compactMap({ $0 }) {
            guard value.utf8.count <= 2048, !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { throw Failure.invalid }
        }
        if scheme == "rdp" {
            guard components.path.isEmpty || components.path == "/", let host = components.host,
                  let request = ConnectionRequest(host: host, port: String(components.port ?? 3389),
                                                  username: username ?? "", password: password ?? "",
                                                  type: .windows, remoteProtocol: .rdp) else { throw Failure.invalid }
            target = .temporary(request)
        } else if scheme == "vnc" || (scheme == "screens" && !isActionRoute) {
            guard components.path.isEmpty || components.path == "/", let host = components.host,
                  let request = ConnectionRequest(host: host, port: String(components.port ?? 5900), username: username ?? "", password: password ?? "", remoteProtocol: .rfb) else { throw Failure.invalid }
            target = .temporary(request)
        } else {
            guard components.port == nil else { throw Failure.invalid }
            switch hostLower {
            case "connect":
                guard components.path.isEmpty || components.path == "/", let host = query["host"] else { throw Failure.invalid }
                let proto: RemoteDevice.RemoteProtocol? = query["protocol"].flatMap { RemoteDevice.RemoteProtocol(rawValue: $0.uppercased()) }
                let defaultPort = proto == .rdp ? "3389" : "5900"
                let deviceType: RemoteDevice.DeviceType = proto == .rdp ? .windows : .mac
                var sshSettings: SSHConnectionSettings? = nil
                if let sshHost = query["sshHost"]?.trimmingCharacters(in: .whitespacesAndNewlines), !sshHost.isEmpty {
                    let sshPortStr = query["sshPort"] ?? "22"
                    guard let sshPort = UInt16(sshPortStr), sshPort > 0,
                          let sshAddress = SSHServerAddress(host: sshHost, port: sshPort) else { throw Failure.invalid }
                    let sshUser = (query["sshUser"] ?? username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let settings = SSHConnectionSettings(
                        server: sshAddress,
                        username: sshUser,
                        authentication: .password
                    ) else { throw Failure.invalid }
                    sshSettings = settings
                }
                guard let request = ConnectionRequest(host: host, port: query["port"] ?? defaultPort,
                                                      name: query["name"] ?? "", username: username ?? "", password: password ?? "",
                                                      type: deviceType, remoteProtocol: proto, ssh: sshSettings) else { throw Failure.invalid }
                target = .temporary(request)
            case "saved":
                guard query["host"] == nil, query["port"] == nil, query["sshHost"] == nil else { throw Failure.invalid }
                let selector = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if let id = UUID(uuidString: selector), query["name"] == nil { target = .saved(id) }
                else if selector.isEmpty, let name = query["name"], !name.trimmingCharacters(in: .whitespaces).isEmpty { target = .savedName(name) }
                else { throw Failure.invalid }
            default: throw Failure.invalid
            }
        }
    }

    public struct Resolved {
        public let device: RemoteDevice
        public let password: String?
        public let isTemporary: Bool
        public let observeOnly: Bool?
        public var requiresIndependentSession: Bool { isTemporary || observeOnly != nil }
    }

    public func resolve(devices: [RemoteDevice], passwordForDevice: (RemoteDevice) -> String?) throws -> Resolved {
        let saved: RemoteDevice
        switch target {
        case .temporary(let request):
            return Resolved(device: request.device, password: request.password, isTemporary: true, observeOnly: observeOnly)
        case .saved(let id):
            guard let device = devices.first(where: { $0.id == id }) else { throw Failure.missingSavedComputer }
            saved = device
        case .savedName(let name):
            let byName = devices.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            var matches = byName.isEmpty ? devices.filter { $0.host.caseInsensitiveCompare(name) == .orderedSame } : byName
            if let username, matches.count > 1 { matches = matches.filter { $0.username == username } }
            guard !matches.isEmpty else { throw Failure.missingSavedComputer }
            guard matches.count == 1 else { throw Failure.ambiguousSavedComputer }
            saved = matches[0]
        }
        var device = saved
        if let username {
            device.username = username.isEmpty ? nil : username
            device.authMethod = username.isEmpty ? .vncPassword : .macAccount
        }
        // A changed account cannot silently receive a password stored for another account.
        let credential = password ?? (username == nil || username == saved.username ? passwordForDevice(saved) : nil)
        return Resolved(device: device, password: credential,
                        isTemporary: username != nil || password != nil, observeOnly: observeOnly)
    }

    public static func savedURL(for deviceID: UUID, observeOnly: Bool? = nil) -> URL {
        var components = URLComponents()
        components.scheme = "aetherscreens"
        components.host = "saved"
        components.path = "/" + deviceID.uuidString
        if let observeOnly { components.queryItems = [URLQueryItem(name: "observe", value: observeOnly ? "true" : "false")] }
        return components.url!
    }

    /// Generates a credential-free shareable connection link (`aetherscreens://connect?...`) including protocol and SSH tunnel settings.
    public static func connectURL(for device: RemoteDevice, observeOnly: Bool? = nil) -> URL {
        var components = URLComponents()
        components.scheme = "aetherscreens"
        components.host = "connect"
        var items: [URLQueryItem] = [
            URLQueryItem(name: "host", value: device.host),
            URLQueryItem(name: "port", value: String(device.port)),
            URLQueryItem(name: "protocol", value: device.remoteProtocol.rawValue)
        ]
        if !device.name.isEmpty, device.name != device.host {
            items.append(URLQueryItem(name: "name", value: device.name))
        }
        if let username = device.username, !username.isEmpty {
            items.append(URLQueryItem(name: "username", value: username))
        }
        if let ssh = device.ssh, !ssh.server.host.isEmpty {
            items.append(URLQueryItem(name: "sshHost", value: ssh.server.host))
            items.append(URLQueryItem(name: "sshPort", value: String(ssh.server.port)))
            if !ssh.username.isEmpty {
                items.append(URLQueryItem(name: "sshUser", value: ssh.username))
            }
        }
        if let observeOnly {
            items.append(URLQueryItem(name: "observe", value: observeOnly ? "true" : "false"))
        }
        components.queryItems = items
        return components.url!
    }
}
