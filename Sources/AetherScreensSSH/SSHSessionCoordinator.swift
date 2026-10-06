import Foundation
import NIOSSH

/// Serializes tunnel ownership across reconnect, trust review and explicit close.
@MainActor
public final class SSHSessionCoordinator {
    public enum TrustDecision: Sendable { case cancel, once, remember }
    public enum Failure: Error { case missingCredential, credentialMismatch, trustCancelled }
    private let store: SSHKeychainStore
    private var generation = UUID()
    private var session: SSHRemoteSession?
    private var closing: Task<Void, Never>?
    private var probeTask: Task<SSHHostKeyIdentity, Error>?
    private var networkTask: Task<SSHRemoteSession, Error>?
    public init(store: SSHKeychainStore = .shared) { self.store = store }

    /// Invalidates pending completions immediately; returns cleanup to await.
    @discardableResult
    public func stop() -> Task<Void, Never> {
        generation = UUID()
        let pendingProbe = probeTask; pendingProbe?.cancel(); probeTask = nil
        let pendingConnection = networkTask; pendingConnection?.cancel(); networkTask = nil
        let previous = session; session = nil
        let oldClosing = closing
        let task = Task {
            await oldClosing?.value
            if let pendingProbe { _ = try? await pendingProbe.value }
            if let pendingConnection, let opened = try? await pendingConnection.value { try? await opened.close() }
            if let previous { try? await previous.close() }
        }
        closing = task
        return task
    }

    public func connect(deviceID: UUID, configuration: SSHConfiguration, destinationPort: UInt16,
                        credentials: SSHSessionCredentials? = nil, temporary: Bool,
                        review: @MainActor (SSHHostKeyIdentity) async -> TrustDecision) async throws -> SSHLoopbackTunnel {
        let cleanup = stop()
        let attempt = generation
        await cleanup.value
        try check(attempt)
        let store = self.store
        let loaded = try await Task.detached {
            try temporary ? credentials : credentials ?? store.load(for: deviceID, configuration: configuration)
        }.value
        try check(attempt)
        guard let loaded else { throw Failure.missingCredential }
        switch (configuration.authentication, loaded) {
        case (.password, .password), (.ed25519, .ed25519PrivateKey): break
        default: throw Failure.credentialMismatch
        }
        var identity = try await Task.detached { try store.trustedKey(for: configuration) }.value
        try check(attempt)
        if identity == nil {
            let probe = Task { try await SSHServerKeyProbe.inspect(host: configuration.host, port: Int(configuration.port)) }
            probeTask = probe
            let observed = try await withTaskCancellationHandler(operation: { try await probe.value }, onCancel: { probe.cancel() })
            try check(attempt)
            probeTask = nil
            let decision = await review(observed)
            try check(attempt)
            switch decision {
            case .cancel: throw Failure.trustCancelled
            case .once: break
            case .remember:
                guard !temporary else { throw Failure.trustCancelled }
                try await Task.detached { try store.approve(observed, for: configuration) }.value
                try check(attempt)
            }
            identity = observed
        }
        guard let identity else { throw Failure.trustCancelled }
        let key = try NIOSSHPublicKey(openSSHPublicKey: identity.openSSHKey)
        let connection = Task {
            try await SSHRemoteSession.connect(host: configuration.host, port: Int(configuration.port),
                username: configuration.username, credentials: loaded, trustedServerKey: key,
                destinationHost: configuration.destinationHost, destinationPort: Int(destinationPort))
        }
        networkTask = connection
        let opened = try await withTaskCancellationHandler(operation: { try await connection.value }, onCancel: { connection.cancel() })
        do { try check(attempt) }
        catch { try? await opened.close(); throw error }
        networkTask = nil
        session = opened
        return opened.tunnel
    }

    private func check(_ attempt: UUID) throws {
        try Task.checkCancellation()
        guard generation == attempt else { throw CancellationError() }
    }
}
