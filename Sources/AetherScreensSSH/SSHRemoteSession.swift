import Foundation
import Citadel
import Crypto
import NIO
import NIOSSH

/// Credentials are transient values and are deliberately not Codable.
public enum SSHSessionCredentials: Sendable {
    case password(String)
    case ed25519PrivateKey(String, passphrase: String?)
}

/// Owns both the authenticated SSH socket and its local forwarding listener.
/// A pinned key is mandatory; first-use confirmation belongs to the UI owner.
public actor SSHRemoteSession {
    public enum ConfigurationError: Error, Equatable { case invalidEndpoint, missingCredential, invalidPrivateKey }
    public nonisolated let tunnel: SSHLoopbackTunnel
    private let client: OwnedSSHConnection
    private var closed = false

    private init(client: OwnedSSHConnection, tunnel: SSHLoopbackTunnel) {
        self.client = client; self.tunnel = tunnel
    }

    public static func connect(host: String, port: Int = 22, username: String,
                               credentials: SSHSessionCredentials, trustedServerKey: NIOSSHPublicKey,
                               destinationHost: String = "127.0.0.1", destinationPort: Int = 5900) async throws -> SSHRemoteSession {
        try Task.checkCancellation()
        guard !host.isEmpty, host.utf8.count <= 253,
              !host.contains(where: { $0.isWhitespace || $0 == "/" || $0 == "@" || $0 == "\0" }),
              (1...65535).contains(port), !username.isEmpty,
              username.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }),
              !destinationHost.isEmpty, !destinationHost.contains("\0"), (1...65535).contains(destinationPort) else {
            throw ConfigurationError.invalidEndpoint
        }
        let auth: SSHAuthenticationMethod
        switch credentials {
        case .password(let password):
            guard !password.isEmpty else { throw ConfigurationError.missingCredential }
            auth = .passwordBased(username: username, password: password)
        case .ed25519PrivateKey(let text, let passphrase):
            try SSHPrivateKeyCost.validate(text)
            let key: Curve25519.Signing.PrivateKey
            do { key = try Curve25519.Signing.PrivateKey(sshEd25519: text, decryptionKey: passphrase.map { Data($0.utf8) }) }
            catch { throw ConfigurationError.invalidPrivateKey }
            auth = .ed25519(username: username, privateKey: key)
        }
        try Task.checkCancellation()
        let group = MultiThreadedEventLoopGroup.singleton
        let cancellation = PendingSSHSocket()
        return try await withTaskCancellationHandler(operation: {
            do {
                let socket = try await ClientBootstrap(group: group)
                    .connectTimeout(.seconds(10))
                    .channelOption(ChannelOptions.autoRead, value: false)
                    .channelOption(ChannelOptions.socketOption(.tcp_nodelay), value: 1)
                    .channelInitializer { channel in
                        guard cancellation.install(channel) else {
                            return channel.eventLoop.makeFailedFuture(CancellationError())
                        }
                        return channel.eventLoop.makeSucceededVoidFuture()
                    }.connect(host: host, port: port).get()
                try Task.checkCancellation()
                let client = try await OwnedSSHConnection.authenticate(on: socket, auth: auth,
                    trustedKey: trustedServerKey)
                do {
                    try Task.checkCancellation()
                    let tunnel = try await SSHLoopbackTunnel.start(connection: client, destinationHost: destinationHost, destinationPort: destinationPort)
                    if Task.isCancelled { try? await tunnel.stop(); throw CancellationError() }
                    return SSHRemoteSession(client: client, tunnel: tunnel)
                } catch {
                    try? await client.close()
                    throw error
                }
            } catch {
                cancellation.cancel()
                if Task.isCancelled { throw CancellationError() }
                throw error
            }
        }, onCancel: { cancellation.cancel() })
    }

    /// Idempotent. The SSH connection is closed even if listener teardown fails.
    public func close() async throws {
        guard !closed else { return }
        closed = true
        var failure: Error?
        do { try await tunnel.stop() } catch { failure = error }
        do { try await client.close() } catch { if failure == nil { failure = error } }
        if let failure = failure { throw failure }
    }
}

/// May be touched by task cancellation and the NIO initializer concurrently.
/// Closing a NIO channel safely dispatches to its own event loop.
final class PendingSSHSocket: @unchecked Sendable {
    private let lock = NSLock()
    private var channel: Channel?
    private var cancelled = false
    func install(_ channel: Channel) -> Bool {
        lock.lock()
        self.channel = channel
        let cancelled = self.cancelled
        lock.unlock()
        if cancelled { channel.close(promise: nil) }
        return !cancelled
    }
    func cancel() {
        lock.lock(); cancelled = true; let socket = channel; lock.unlock()
        socket?.close(promise: nil)
    }
}
