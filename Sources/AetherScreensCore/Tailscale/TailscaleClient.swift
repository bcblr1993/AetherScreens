import Foundation

/// Client for interacting with the official Tailscale REST API v2.
public final class TailscaleClient: Sendable {

    public enum TailscaleError: LocalizedError, Sendable {
        case invalidURL
        case unauthorized
        case httpError(statusCode: Int, message: String)
        case decodingError(String)

        public var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid Tailscale API endpoint URL."
            case .unauthorized: return "Tailscale authentication failed. Check your API access token."
            case .httpError(let code, let msg): return "Tailscale HTTP \(code): \(msg)"
            case .decodingError(let msg): return "Failed to parse Tailscale response: \(msg)"
            }
        }
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
