import Foundation

/// Client for interacting with the official Tailscale REST API v2.
public final class TailscaleClient: Sendable {

    public enum TailscaleError: LocalizedError, Sendable {
        case invalidURL
        case unauthorized
        case httpError(statusCode: Int, message: String)
        case decodingError(String)
        case localCLINotAvailable

        public var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid Tailscale API endpoint URL."
            case .unauthorized: return "Tailscale authentication failed. Check your API access token."
            case .httpError(let code, let msg): return "Tailscale HTTP \(code): \(msg)"
            case .decodingError(let msg): return "Failed to parse Tailscale response: \(msg)"
            case .localCLINotAvailable: return "Local Tailscale CLI is not running. Please enter your Tailscale API Key in Settings or start the Tailscale app."
            }
        }
    }

    private struct LocalStatusEnvelope: Decodable {
        struct PeerNode: Decodable {
            let ID: String?
            let HostName: String?
            let DNSName: String?
            let OS: String?
            let TailscaleIPs: [String]?
            let Online: Bool?
            let LastSeen: String?
        }
        let Peer: [String: PeerNode]?
    }

    /// Parses the JSON output of `tailscale status --json` into `TailscaleDevice` records.
    public static func parseLocalStatusJSON(_ data: Data) throws -> [TailscaleDevice] {
        do {
            let envelope = try JSONDecoder().decode(LocalStatusEnvelope.self, from: data)
            guard let peers = envelope.Peer else { return [] }
            return peers.values.compactMap { peer -> TailscaleDevice? in
                let ips = peer.TailscaleIPs ?? []
                guard !ips.isEmpty else { return nil }
                let osName = peer.OS ?? "other"
                let dns = (peer.DNSName ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "."))
                let hostname = peer.HostName ?? ""
                let dev = TailscaleDevice(
                    id: peer.ID ?? (dns.isEmpty ? hostname : dns),
                    name: dns.isEmpty ? hostname : dns,
                    hostname: hostname,
                    addresses: ips,
                    os: osName,
                    authorized: true,
                    connectedToControl: peer.Online ?? false,
                    lastSeen: peer.LastSeen
                )
                return dev.isMobileClientOnly ? nil : dev
            }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        } catch {
            throw TailscaleError.decodingError(error.localizedDescription)
        }
    }

    /// Zero-config local Tailscale discovery on macOS using the installed Tailscale CLI (`tailscale status --json`).
    public static func fetchLocalStatusDevices() async throws -> [TailscaleDevice] {
        #if os(macOS)
        let candidatePaths = [
            "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
            "/opt/homebrew/bin/tailscale",
            "/usr/local/bin/tailscale"
        ]
        guard let executablePath = candidatePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw TailscaleError.localCLINotAvailable
        }
        return try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = ["status", "--json"]
            let outPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = Pipe()
            try process.run()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0, !data.isEmpty else {
                throw TailscaleError.localCLINotAvailable
            }
            return try parseLocalStatusJSON(data)
        }.value
        #else
        throw TailscaleError.localCLINotAvailable
        #endif
    }

    private let apiKey: String
    private let tailnet: String
    private let session: URLSession

    public init(apiKey: String, tailnet: String = "-", session: URLSession = .shared) {
        self.apiKey = apiKey
        self.tailnet = tailnet.isEmpty ? "-" : tailnet
        self.session = session
    }

    /// Fetches all devices registered under the current Tailnet.
    public func fetchDevices() async throws -> [TailscaleDevice] {
        guard let url = URL(string: "https://api.tailscale.com/api/v2/tailnet/\(tailnet)/devices") else {
            throw TailscaleError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TailscaleError.httpError(statusCode: 0, message: "Unknown response type")
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw TailscaleError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw TailscaleError.httpError(statusCode: httpResponse.statusCode, message: msg)
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let result = try decoder.decode(TailscaleDevicesResponse.self, from: data)
            return result.devices
        } catch {
            throw TailscaleError.decodingError(error.localizedDescription)
        }
    }
}
