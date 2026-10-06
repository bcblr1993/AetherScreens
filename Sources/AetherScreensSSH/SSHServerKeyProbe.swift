import NIO
import NIOSSH

/// Fetches public host-key information without offering any user credentials.
/// The key remains untrusted; callers must obtain approval before using it.
public enum SSHServerKeyProbe {
    public enum Failure: Error { case invalidEndpoint, reviewRequired }

    public static func inspect(host: String, port: Int = 22) async throws -> SSHHostKeyIdentity {
        try Task.checkCancellation()
        guard !host.isEmpty, host.utf8.count <= 253,
              !host.contains(where: { $0.isWhitespace || $0 == "/" || $0 == "@" || $0 == "\0" }),
              (1...65535).contains(port) else { throw Failure.invalidEndpoint }
        let cancellation = PendingSSHSocket()
        return try await withTaskCancellationHandler(operation: {
            do {
                let channel = try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
                    .connectTimeout(.seconds(10))
                    .channelOption(ChannelOptions.autoRead, value: false)
                    .channelInitializer { channel in
                        guard cancellation.install(channel) else {
                            return channel.eventLoop.makeFailedFuture(CancellationError())
                        }
                        return channel.eventLoop.makeSucceededVoidFuture()
                    }.connect(host: host, port: port).get()
                let result = try await channel.eventLoop.submit {
                    guard channel.isActive else { throw ChannelError.ioOnClosedChannel }
                    // Cancellation may close the socket before this submission
                    // runs. Create a promise only after checking on its loop.
                    let promise = channel.eventLoop.makePromise(of: SSHHostKeyIdentity.self)
                    let observer = KeyObservation(promise: promise)
                    let ssh = NIOSSHHandler(role: .client(SSHClientConfiguration(
                        userAuthDelegate: NoCredentials(), serverAuthDelegate: observer)),
                        allocator: channel.allocator, inboundChildChannelInitializer: nil)
                    do { try channel.pipeline.syncOperations.addHandlers(ssh, observer) }
                    catch { observer.failSetup(error); throw error }
                    return promise.futureResult
                }.get()
                try await channel.setOption(ChannelOptions.autoRead, value: true).get()
                let identity = try await result.get()
                cancellation.cancel()
                try await channel.closeFuture.get()
                try Task.checkCancellation()
                return identity
            } catch {
                cancellation.cancel()
                if Task.isCancelled { throw CancellationError() }
                throw error
            }
        }, onCancel: { cancellation.cancel() })
    }
}

private struct NoCredentials: NIOSSHClientUserAuthenticationDelegate {
    func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>) {
        nextChallengePromise.succeed(nil)
    }
}

/// All state is confined to the socket event loop.
private final class KeyObservation: ChannelInboundHandler, NIOSSHClientServerAuthenticationDelegate {
    typealias InboundIn = Any
    private let promise: EventLoopPromise<SSHHostKeyIdentity>
    private var completed = false
    private var deadline: Scheduled<Void>?
    init(promise: EventLoopPromise<SSHHostKeyIdentity>) { self.promise = promise }
    func failSetup(_ error: Error) { finish(.failure(error)) }
    private func finish(_ result: Result<SSHHostKeyIdentity, Error>) {
        guard !completed else { return }
        completed = true; deadline?.cancel(); promise.completeWith(result)
    }
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        finish(.success(SSHHostKeyIdentity(key: hostKey)))
        // Reject intentionally: learning a key must never authenticate a user.
        validationCompletePromise.fail(SSHServerKeyProbe.Failure.reviewRequired)
    }
    func handlerAdded(context: ChannelHandlerContext) {
        let channel = context.channel
        deadline = context.eventLoop.scheduleTask(in: .seconds(10)) { [self, channel] in
            finish(.failure(ChannelError.connectTimeout(.seconds(10))))
            channel.close(promise: nil)
        }
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        finish(.failure(error)); context.close(promise: nil)
    }
    func channelInactive(context: ChannelHandlerContext) {
        finish(.failure(ChannelError.ioOnClosedChannel)); context.fireChannelInactive()
    }
    func handlerRemoved(context: ChannelHandlerContext) { finish(.failure(ChannelError.ioOnClosedChannel)) }
}
