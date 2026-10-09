import Foundation
import NIOCore
import NIOPosix
import NIOSSH

/// An authenticated, host-verified SSH direct-TCP forwarding listener bound only
/// to IPv4 loopback. A stopped/replaced attempt cannot publish a late listener.
public actor SSHForwardingTunnel {
    public enum Failure: Error, Equatable {
        case cancelled, closed, timedOut, authenticationFailed, hostKeyRejected
        case unsupportedAuthentication, invalidForward, invalidData
    }
    public typealias HostDecision = @Sendable (SSHHostKey, SSHHostTrustStore.Assessment) async -> Bool
    private static let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var attempt: SSHTunnelAttempt?
    private var boundPort: UInt16?
    private let handshakeTimeout: TimeAmount
    public var localPort: UInt16? { attempt?.isActive == true ? boundPort : nil }

    public init() { handshakeTimeout = .seconds(20) }
    init(handshakeTimeout: TimeAmount) { self.handshakeTimeout = handshakeTimeout }
    deinit { attempt?.cancel() }

    public func start(settings: SSHConnectionSettings, password: String = "", privateKeyData: Data? = nil, remotePort: UInt16,
                      trust: SSHHostTrustStore = .shared,
                      decideHost: @escaping HostDecision) async throws -> UInt16 {
        stop()
        let credential: SSHAuthenticationDelegate.Credential
        switch settings.authentication {
        case .password: credential = .password(password)
        case .privateKey:
            guard let privateKeyData else { throw Failure.unsupportedAuthentication }
            credential = .key(try SSHPrivateKey.decode(privateKeyData))
        }
        guard remotePort > 0 else { throw Failure.invalidForward }
        let loop = Self.group.next()
        let candidate = SSHTunnelAttempt(ready: loop.makePromise(of: Void.self), loop: loop, timeout: handshakeTimeout)
        attempt = candidate
        candidate.armTimeout()
        do {
            return try await withTaskCancellationHandler(operation: {
                let ssh = try await ClientBootstrap(group: loop)
                    .connectTimeout(.seconds(20))
                    .channelOption(ChannelOptions.socketOption(.tcp_nodelay), value: 1)
                    .channelInitializer { channel in
                        guard candidate.register(channel) else { return loop.makeFailedFuture(Failure.cancelled) }
                        let user = SSHAuthenticationDelegate(username: settings.username, credential: credential)
                        let host = SSHTrustDelegate(server: settings.server, trust: trust, candidate: candidate, decide: decideHost)
                        return channel.eventLoop.makeCompletedFuture {
                            try channel.pipeline.syncOperations.addHandlers([
                                NIOSSHHandler(role: .client(.init(userAuthDelegate: user, serverAuthDelegate: host)),
                                              allocator: channel.allocator, inboundChildChannelInitializer: nil),
                                SSHAuthenticationReady(candidate: candidate)
                            ])
                        }
                    }
                    .connect(host: settings.server.host, port: Int(settings.server.port)).get()
                ssh.closeFuture.whenComplete { _ in candidate.cancel(reason: Failure.closed) }
                try await candidate.ready.promise.futureResult.get()
                candidate.pauseTimeout()
                try candidate.withActive {}
                let boundHandler = try await loop.submit {
                    NIOLoopBound(try ssh.pipeline.syncOperations.handler(type: NIOSSHHandler.self), eventLoop: loop)
                }.get()
                let listener = try await ServerBootstrap(group: loop, childGroup: loop)
                    .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                    .childChannelOption(ChannelOptions.socketOption(.tcp_nodelay), value: 1)
                    .childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: true)
                    .serverChannelInitializer { channel in
                        candidate.register(channel, role: .listener) ? loop.makeSucceededFuture(()) : loop.makeFailedFuture(Failure.cancelled)
                    }
                    .childChannelInitializer { socket in
                        guard candidate.register(socket, role: .forwarded), let origin = socket.remoteAddress else {
                            return loop.makeFailedFuture(Failure.cancelled)
                        }
                        let promise = loop.makePromise(of: Channel.self)
                        boundHandler.value.createChannel(promise, channelType: .directTCPIP(.init(
                            targetHost: settings.remoteHost, targetPort: Int(remotePort), originatorAddress: origin))) { child, type in
                            guard case .directTCPIP = type, candidate.register(child, role: .forwarded) else {
                                return loop.makeFailedFuture(Failure.invalidForward)
                            }
                            return child.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).flatMap {
                                loop.makeCompletedFuture {
                                    let (remote, local) = SSHForwardingGlue.matchedPair()
                                    try child.pipeline.syncOperations.addHandlers([SSHForwardingCodec(), remote])
                                    try socket.pipeline.syncOperations.addHandler(local)
                                }
                            }
                        }
                        return promise.futureResult.map { _ in }
                    }
                    .bind(host: "127.0.0.1", port: 0).get()
                guard attempt === candidate, candidate.isActive, let port = listener.localAddress?.port,
                      let number = UInt16(exactly: port), number > 0 else { throw Failure.cancelled }
                boundPort = number
                return number
            }, onCancel: { candidate.cancel() })
        } catch {
            candidate.cancel()
            if attempt === candidate { attempt = nil; boundPort = nil }
            throw error
        }
    }

    public func stop() {
        attempt?.cancel()
        attempt = nil
        boundPort = nil
    }

    /// Retain the encrypted transport while a final RFB packet drains. Stop
    /// accepting local sockets first; a bounded deadline also handles dead peers.
    public func finishForwardedConnections() async {
        guard let candidate = attempt else { return }
        boundPort = nil
        let streams = candidate.stopAccepting()
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for stream in streams { try? await stream.closeFuture.get() }
            }
            group.addTask { try? await Task.sleep(nanoseconds: 3_000_000_000) }
            await group.next()
            candidate.cancel()
            group.cancelAll()
        }
        if attempt === candidate { attempt = nil }
    }
}

/// One completion despite races between cancellation, timeout and protocol events.
private final class SSHOnce: @unchecked Sendable {
    let promise: EventLoopPromise<Void>
    private let lock = NSLock()
    private var finished = false
    init(_ promise: EventLoopPromise<Void>) { self.promise = promise }
    func finish(_ result: Result<Void, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true; lock.unlock()
        promise.completeWith(result)
    }
}

private final class SSHTunnelAttempt: @unchecked Sendable {
    enum Role { case transport, listener, forwarded }
    let ready: SSHOnce
    private let lock = NSLock()
    private var active = true
    private var channels: [ObjectIdentifier: Channel] = [:]
    private var roles: [ObjectIdentifier: Role] = [:]
    private var accepting = true
    private var cancellations: [@Sendable () -> Void] = []
    private let loop: EventLoop
    private let timeout: TimeAmount
    private var timeoutGeneration = UUID()
    private var timeoutTask: Scheduled<Void>?
    init(ready: EventLoopPromise<Void>, loop: EventLoop, timeout: TimeAmount) {
        self.ready = SSHOnce(ready); self.loop = loop; self.timeout = timeout
    }
    func armTimeout() {
        lock.lock(); defer { lock.unlock() }
        guard active else { return }
        timeoutTask?.cancel()
        timeoutGeneration = UUID()
        let generation = timeoutGeneration
        timeoutTask = loop.scheduleTask(in: timeout) { [weak self] in
            self?.cancel(reason: SSHForwardingTunnel.Failure.timedOut, requiredTimeoutGeneration: generation)
        }
    }
    func pauseTimeout() {
        lock.lock(); defer { lock.unlock() }
        timeoutGeneration = UUID()
        timeoutTask?.cancel(); timeoutTask = nil
    }
    var isActive: Bool { lock.lock(); defer { lock.unlock() }; return active }
    func withActive<T>(_ operation: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        guard active else { throw SSHForwardingTunnel.Failure.cancelled }
        return try operation()
    }
    func register(_ channel: Channel, role: Role = .transport) -> Bool {
        lock.lock()
        guard active, accepting || role == .transport else { lock.unlock(); channel.close(promise: nil); return false }
        let id = ObjectIdentifier(channel)
        channels[id] = channel; roles[id] = role; lock.unlock()
        channel.closeFuture.whenComplete { [weak self] _ in
            guard let self else { return }
            self.lock.lock(); self.channels.removeValue(forKey: id); self.roles.removeValue(forKey: id); self.lock.unlock()
        }
        return true
    }
    func stopAccepting() -> [Channel] {
        lock.lock()
        accepting = false
        let listeners = channels.filter { roles[$0.key] == .listener }.map(\.value)
        let streams = channels.filter { roles[$0.key] == .forwarded }.map(\.value)
        lock.unlock()
        listeners.forEach { $0.close(promise: nil) }
        return streams
    }
    func onCancel(_ operation: @escaping @Sendable () -> Void) {
        lock.lock()
        if active { cancellations.append(operation); lock.unlock() }
        else { lock.unlock(); operation() }
    }
    func cancel(reason: Error = SSHForwardingTunnel.Failure.cancelled, requiredTimeoutGeneration: UUID? = nil) {
        lock.lock()
        guard active, requiredTimeoutGeneration == nil || requiredTimeoutGeneration == timeoutGeneration else { lock.unlock(); return }
        active = false
        timeoutGeneration = UUID()
        if requiredTimeoutGeneration == nil { timeoutTask?.cancel() }
        timeoutTask = nil
        let channels = Array(channels.values), cancellations = self.cancellations
        self.channels.removeAll(); self.cancellations.removeAll(); lock.unlock()
        ready.finish(.failure(reason))
        cancellations.forEach { $0() }
        channels.forEach { $0.close(promise: nil) }
    }
}

private final class SSHAuthenticationDelegate: NIOSSHClientUserAuthenticationDelegate {
    enum Credential: Sendable { case password(String), key(NIOSSHPrivateKey) }
    private let username: String, credential: Credential
    private var offered = false // confined to the SSH channel's event loop
    init(username: String, credential: Credential) { self.username = username; self.credential = credential }
    func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods,
                                nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>) {
        guard !offered else {
            nextChallengePromise.fail(SSHForwardingTunnel.Failure.authenticationFailed); return
        }
        let offer: NIOSSHUserAuthenticationOffer.Offer
        switch credential {
        case .password(let password):
            guard availableMethods.contains(.password) else { nextChallengePromise.fail(SSHForwardingTunnel.Failure.authenticationFailed); return }
            offer = .password(.init(password: password))
        case .key(let key):
            guard availableMethods.contains(.publicKey) else { nextChallengePromise.fail(SSHForwardingTunnel.Failure.authenticationFailed); return }
            offer = .privateKey(.init(privateKey: key))
        }
        offered = true
        nextChallengePromise.succeed(.init(username: username, serviceName: "", offer: offer))
    }
}

private final class SSHTrustDelegate: NIOSSHClientServerAuthenticationDelegate {
    private let server: SSHServerAddress, trust: SSHHostTrustStore, candidate: SSHTunnelAttempt
    private let decide: SSHForwardingTunnel.HostDecision
    init(server: SSHServerAddress, trust: SSHHostTrustStore, candidate: SSHTunnelAttempt,
         decide: @escaping SSHForwardingTunnel.HostDecision) {
        self.server = server; self.trust = trust; self.candidate = candidate; self.decide = decide
    }
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let completion = SSHOnce(validationCompletePromise)
        candidate.onCancel { completion.finish(.failure(SSHForwardingTunnel.Failure.cancelled)) }
        do {
            let encoded = String(openSSHPublicKey: hostKey).split(separator: " ")
            guard encoded.count == 2, let data = Data(base64Encoded: String(encoded[1])) else {
                throw SSHForwardingTunnel.Failure.invalidData
            }
            let key = try SSHHostKey(validatedKeyBlob: data)
            let assessment = try trust.assess(key, at: server)
            if assessment == .trusted {
                try candidate.withActive {}
                completion.finish(.success(()))
                return
            }
            candidate.pauseTimeout() // Human identity confirmation is not a network stall.
            let candidate = candidate, server = server, trust = trust, decide = decide
            let task = Task {
                guard candidate.isActive else { return }
                guard await decide(key, assessment) else {
                    completion.finish(.failure(SSHForwardingTunnel.Failure.hostKeyRejected)); return
                }
                do {
                    try candidate.withActive {
                        let previous: SSHHostKey?
                        if case .changed(let key) = assessment { previous = key } else { previous = nil }
                        try trust.approve(key, at: server, replacing: previous)
                    }
                    candidate.armTimeout()
                    completion.finish(.success(()))
                } catch { completion.finish(.failure(error)) }
            }
            candidate.onCancel { task.cancel() }
        } catch { completion.finish(.failure(error)) }
    }
}

private final class SSHAuthenticationReady: ChannelInboundHandler {
    typealias InboundIn = Any
    private let candidate: SSHTunnelAttempt
    init(candidate: SSHTunnelAttempt) { self.candidate = candidate }
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is UserAuthSuccessEvent { candidate.ready.finish(.success(())) }
        context.fireUserInboundEventTriggered(event)
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        candidate.ready.finish(.failure(error)); candidate.cancel(reason: error)
        context.close(promise: nil)
    }
    func channelInactive(context: ChannelHandlerContext) {
        candidate.cancel(reason: SSHForwardingTunnel.Failure.closed)
        context.fireChannelInactive()
    }
}

final class SSHForwardingCodec: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let data = unwrapInboundIn(data)
        guard case .channel = data.type, case .byteBuffer(let buffer) = data.data else {
            context.fireErrorCaught(SSHForwardingTunnel.Failure.invalidData); return
        }
        context.fireChannelRead(wrapInboundOut(buffer))
    }
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        context.write(wrapOutboundOut(.init(type: .channel, data: .byteBuffer(unwrapOutboundIn(data)))), promise: promise)
    }
}
