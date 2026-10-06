import Foundation
import NIO

/// Resolved endpoints of the authenticated socket, never the local RFB adapter.
/// This transient metadata is deliberately not Codable or logged.
public struct SSHTransportEndpoints: Sendable {
    public let localAddress: Data
    public let remoteAddress: Data
    public let destinationIsSSHHost: Bool

    init?(local: SocketAddress?, remote: SocketAddress?, destinationHost: String) {
        guard let local = Self.bytes(local), let remote = Self.bytes(remote),
              local.count == remote.count else { return nil }
        self.localAddress = local
        self.remoteAddress = remote
        let destination = try? SocketAddress(ipAddress: destinationHost, port: 0)
        let address = Self.bytes(destination)
        // A separate forwarded host may be on another network behind the SSH
        // server. Its route cannot be inferred from the authenticated socket.
        self.destinationIsSSHHost = address.map { Self.isLoopback($0) || $0 == remote } ?? false
    }

    private static func bytes(_ address: SocketAddress?) -> Data? {
        switch address {
        case .v4(let value):
            return withUnsafeBytes(of: value.address.sin_addr) { Data($0) }
        case .v6(let value):
            let bytes = withUnsafeBytes(of: value.address.sin6_addr) { Data($0) }
            if bytes.prefix(12) == Data(Array(repeating: 0, count: 10) + [255, 255]) {
                return Data(bytes.suffix(4))
            }
            return bytes
        default: return nil
        }
    }

    private static func isLoopback(_ address: Data) -> Bool {
        address.count == 4 ? address.first == 127
            : address == Data(Array(repeating: 0, count: 15) + [1])
    }
}
