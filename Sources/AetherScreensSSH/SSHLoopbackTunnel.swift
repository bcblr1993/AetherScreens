import Citadel
import NIO

/// Encrypted loopback adapter for existing TCP clients. All mutable lifecycle
/// state and both sides of every relay are confined to the SSH event loop.
public final class SSHLoopbackTunnel: @unchecked Sendable {
    public let port: Int
    public let transportEndpoints: SSHTransportEndpoints?
    private let listener: Channel
    private let registry: TunnelChannels
    private let roundTripTimeProvider: (@Sendable () async -> Double?)?

    private init(listener: Channel, registry: TunnelChannels, port: Int,
                 transportEndpoints: SSHTransportEndpoints?,
                 roundTripTimeProvider: (@Sendable () async -> Double?)?) {
        self.listener = listener; self.registry = registry; self.port = port
        self.transportEndpoints = transportEndpoints
        self.roundTripTimeProvider = roundTripTimeProvider
    }

    public static func start(client: SSHClient, destinationHost: String, destinationPort: Int) async throws -> SSHLoopbackTunnel {
        guard !destinationHost.isEmpty, !destinationHost.contains("\0"), (1...65535).contains(destinationPort) else {
            throw SSHDirectStream.ConfigurationError.invalidDestination
        }
        return try await start(loop: client.eventLoop, opener: EventLoopStreamOpener(client: client),
                               destinationHost: destinationHost, destinationPort: destinationPort,
                               transportEndpoints: nil, roundTripTimeProvider: nil)
    }

    static func start(connection: OwnedSSHConnection, destinationHost: String, destinationPort: Int) async throws -> SSHLoopbackTunnel {
        let endpoints = try await connection.transportEndpoints(destinationHost: destinationHost)
        return try await start(loop: connection.eventLoop, opener: connection,
                        destinationHost: destinationHost, destinationPort: destinationPort,
                        transportEndpoints: endpoints,
                        roundTripTimeProvider: { await connection.transportRoundTripTime() })
    }

    private static func start(loop: EventLoop, opener: any SSHStreamOpening,
                              destinationHost: String, destinationPort: Int,
                              transportEndpoints: SSHTransportEndpoints?,
                              roundTripTimeProvider: (@Sendable () async -> Double?)?) async throws -> SSHLoopbackTunnel {
        let registry = TunnelChannels(loop: loop)
        let listener = try await ServerBootstrap(group: loop)
            .childChannelOption(ChannelOptions.autoRead, value: false)
            .childChannelInitializer { local in
                guard registry.add(local) else { return local.eventLoop.makeFailedFuture(ChannelError.ioOnClosedChannel) }
                return local.eventLoop.makeFutureWithTask {
                    let stream = try await opener.open(host: destinationHost, port: destinationPort) { remote in
                        guard registry.add(remote) else { return remote.eventLoop.makeFailedFuture(ChannelError.ioOnClosedChannel) }
                        do {
                            try remote.pipeline.syncOperations.addHandler(TunnelRelay(peer: local))
                            try local.pipeline.syncOperations.addHandler(TunnelRelay(peer: remote))
                            return remote.setOption(ChannelOptions.autoRead, value: false)
                        } catch { return remote.eventLoop.makeFailedFuture(error) }
                    }
                    // Channel opening can race stop(). Recheck under the same
                    // loop before enabling either source to read any payload.
                    try await local.eventLoop.submit {
                        guard !registry.stopped else {
                            stream.close(promise: nil)
                            throw ChannelError.ioOnClosedChannel
                        }
                        stream.read()
                    }.get()
                }
            }.bind(host: "127.0.0.1", port: 0).get()
        guard let port = listener.localAddress?.port else {
            try await listener.close().get()
            throw SSHDirectStream.ConfigurationError.invalidDestination
        }
        return SSHLoopbackTunnel(listener: listener, registry: registry, port: port,
                                 transportEndpoints: transportEndpoints,
                                 roundTripTimeProvider: roundTripTimeProvider)
    }

    /// TCP RTT of the authenticated SSH transport. Excludes forwarded-hop,
    /// remote application processing and display latency. Never samples the RFB adapter.
    public func transportRoundTripTime() async -> Double? {
        guard let roundTripTimeProvider, await isActive() else { return nil }
        let result = await roundTripTimeProvider()
        return await isActive() ? result : nil
    }

    private func isActive() async -> Bool {
        (try? await listener.eventLoop.submit {
            !self.registry.stopped && self.listener.isActive
        }.get()) ?? false
    }

    /// Stops accepting, closes all accepted local/SSH channels, and leaves the
    /// caller-owned SSH client for its owner to close or reuse explicitly.
    public func stop() async throws {
        try await listener.eventLoop.flatSubmit {
            self.registry.stopped = true
            let closed = self.registry.closeAll()
            self.listener.close(promise: nil)
            return closed.and(self.listener.closeFuture).map { _ in () }
        }.get()
    }
}

private final class TunnelChannels: @unchecked Sendable {
    let loop: EventLoop
    var stopped = false
    var channels: [ObjectIdentifier: Channel] = [:]
    init(loop: EventLoop) { self.loop = loop }
    func add(_ channel: Channel) -> Bool {
        loop.preconditionInEventLoop()
        guard !stopped else { channel.close(promise: nil); return false }
        let id = ObjectIdentifier(channel)
        channels[id] = channel
        channel.closeFuture.whenComplete { [weak self] _ in self?.channels.removeValue(forKey: id) }
        return true
    }
    func closeAll() -> EventLoopFuture<Void> {
        loop.preconditionInEventLoop()
        let current = Array(channels.values)
        for channel in current { channel.close(promise: nil) }
        return EventLoopFuture.andAllSucceed(current.map { $0.closeFuture }, on: loop)
    }
}

private final class TunnelRelay: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    weak var peer: Channel?
    init(peer: Channel) { self.peer = peer }
    func channelActive(context: ChannelHandlerContext) {
        if peer?.isWritable == true { context.read() }
        context.fireChannelActive()
    }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard let peer = peer else { context.close(promise: nil); return }
        peer.write(unwrapInboundIn(data)).whenFailure { _ in
            peer.close(promise: nil)
            context.close(promise: nil)
        }
    }
    func channelReadComplete(context: ChannelHandlerContext) {
        peer?.flush()
        if peer?.isWritable == true { context.read() }
        context.fireChannelReadComplete()
    }
    func channelWritabilityChanged(context: ChannelHandlerContext) {
        if context.channel.isWritable { peer?.read() }
        context.fireChannelWritabilityChanged()
    }
    func channelInactive(context: ChannelHandlerContext) {
        peer?.close(promise: nil)
        context.fireChannelInactive()
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        peer?.close(promise: nil); context.close(promise: nil)
    }
}

/// Citadel 0.12.1 does not declare SSHClient Sendable. This immutable adapter
/// exposes only direct channel creation, whose upstream implementation submits
/// every access to the SSH client's event loop; it never mutates client settings.
private final class EventLoopStreamOpener: SSHStreamOpening, @unchecked Sendable {
    private let client: SSHClient
    init(client: SSHClient) { self.client = client }
    func open(host: String, port: Int,
              initialize: @escaping (Channel) -> EventLoopFuture<Void>) async throws -> Channel {
        try await SSHDirectStream.open(client: client, host: host, port: port, initialize: initialize)
    }
}

protocol SSHStreamOpening: Sendable {
    func open(host: String, port: Int,
              initialize: @escaping (Channel) -> EventLoopFuture<Void>) async throws -> Channel
}
