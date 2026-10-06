import Citadel
import NIO
import NIOSSH
import Darwin

/// Internal client lifecycle built on NIOSSH. Every synchronous pipeline/handler
/// operation runs on the owned socket's event loop, including authentication.
final class OwnedSSHConnection: SSHStreamOpening, @unchecked Sendable {
    let eventLoop: EventLoop
    private let channel: Channel
    private let handler: NIOLoopBoundBox<NIOSSHHandler>
    private init(channel: Channel, handler: NIOLoopBoundBox<NIOSSHHandler>) {
        self.channel = channel; self.eventLoop = channel.eventLoop; self.handler = handler
    }
    static func authenticate(on channel: Channel, auth: SSHAuthenticationMethod,
                             trustedKey: NIOSSHPublicKey) async throws -> OwnedSSHConnection {
        let (handler, ready) = try await channel.eventLoop.submit {
            guard channel.isActive else { throw ChannelError.ioOnClosedChannel }
            let ready = channel.eventLoop.makePromise(of: Void.self)
            let observer = SSHAuthenticationReady(promise: ready)
            let handler = NIOSSHHandler(role: .client(SSHClientConfiguration(
                userAuthDelegate: auth, serverAuthDelegate: HostKeyPin.validator(for: trustedKey))),
                allocator: channel.allocator, inboundChildChannelInitializer: nil)
            do { try channel.pipeline.syncOperations.addHandlers(handler, observer) }
            catch { observer.failSetup(error); throw error }
            return (NIOLoopBoundBox(handler, eventLoop: channel.eventLoop), ready.futureResult)
        }.get()
        try await channel.setOption(ChannelOptions.autoRead, value: true).get()
        try await ready.get()
        return OwnedSSHConnection(channel: channel, handler: handler)
    }
    func open(host: String, port: Int,
              initialize: @escaping (Channel) -> EventLoopFuture<Void>) async throws -> Channel {
        let origin = try SocketAddress(ipAddress: "127.0.0.1", port: 0)
        return try await eventLoop.flatSubmit {
            guard self.channel.isActive else { return self.eventLoop.makeFailedFuture(ChannelError.ioOnClosedChannel) }
            let created = self.eventLoop.makePromise(of: Channel.self)
            self.handler.value.createChannel(created, channelType: .directTCPIP(.init(
                targetHost: host, targetPort: port, originatorAddress: origin))) { child, type in
                guard case .directTCPIP = type else { return child.eventLoop.makeFailedFuture(ChannelError.operationUnsupported) }
                do {
                    try child.pipeline.syncOperations.addHandlers(SSHBufferCodec(), BoundedStreamWrites())
                    return initialize(child)
                } catch { return child.eventLoop.makeFailedFuture(error) }
            }
            return created.futureResult
        }.get()
    }
    func close() async throws { try await channel.close().get() }

    func transportEndpoints(destinationHost: String) async throws -> SSHTransportEndpoints? {
        try await eventLoop.submit {
            guard self.channel.isActive else { throw ChannelError.ioOnClosedChannel }
            return SSHTransportEndpoints(local: self.channel.localAddress,
                remote: self.channel.remoteAddress, destinationHost: destinationHost)
        }.get()
    }

    func transportTCPInfo() async throws -> tcp_connection_info {
        guard let provider = channel as? SocketOptionProvider else { throw ChannelError.operationUnsupported }
        let info = try await provider.getTCPConnectionInfo().get()
        return try await eventLoop.submit {
            guard self.channel.isActive else { throw ChannelError.ioOnClosedChannel }
            return info
        }.get()
    }

    func transportRoundTripTime() async -> Double? {
        guard let info = try? await transportTCPInfo() else { return nil }
        return Self.milliseconds(smoothedRTT: info.tcpi_srtt)
    }

    static func milliseconds(smoothedRTT: UInt32) -> Double? {
        // Darwin TCP_CONNECTION_INFO already reports milliseconds. Zero means
        // no usable estimate, including sub-millisecond loopback connections.
        smoothedRTT > 0 ? Double(smoothedRTT) : nil
    }
}

private final class SSHAuthenticationReady: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = Any
    let promise: EventLoopPromise<Void>
    var completed = false
    var deadline: Scheduled<Void>?
    init(promise: EventLoopPromise<Void>) { self.promise = promise }
    func failSetup(_ error: Error) { finish(.failure(error)) }
    func handlerAdded(context: ChannelHandlerContext) {
        let channel = context.channel
        deadline = context.eventLoop.scheduleTask(in: .seconds(10)) { [self, channel] in
            finish(.failure(ChannelError.connectTimeout(.seconds(10))))
            channel.close(promise: nil)
        }
    }
    private func finish(_ result: Result<Void, Error>) {
        guard !completed else { return }
        completed = true; deadline?.cancel(); promise.completeWith(result)
    }
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is UserAuthSuccessEvent { finish(.success(())) }
        context.fireUserInboundEventTriggered(event)
    }
    func channelInactive(context: ChannelHandlerContext) {
        finish(.failure(ChannelError.ioOnClosedChannel)); context.fireChannelInactive()
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        finish(.failure(error)); context.close(promise: nil)
    }
    func handlerRemoved(context: ChannelHandlerContext) { finish(.failure(ChannelError.ioOnClosedChannel)) }
}

private final class SSHBufferCodec: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let packet = unwrapInboundIn(data)
        guard packet.type == .channel, case .byteBuffer(let bytes) = packet.data else {
            context.fireErrorCaught(ChannelError.operationUnsupported); return
        }
        context.fireChannelRead(wrapInboundOut(bytes))
    }
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        context.write(wrapOutboundOut(SSHChannelData(type: .channel,
            data: .byteBuffer(unwrapOutboundIn(data)))), promise: promise)
    }
}
