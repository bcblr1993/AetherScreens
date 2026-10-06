import Citadel
import NIO
import NIOSSH

public enum SSHDirectStream {
    public enum ConfigurationError: Error { case invalidDestination }

    public static func open(client: SSHClient, host: String, port: Int,
                            initialize: @escaping (Channel) -> EventLoopFuture<Void>) async throws -> Channel {
        guard !host.isEmpty, !host.contains("\0"), (1...65535).contains(port) else {
            throw ConfigurationError.invalidDestination
        }
        let origin = try SocketAddress(ipAddress: "127.0.0.1", port: 0)
        return try await client.createDirectTCPIPChannel(using: .init(
            targetHost: host, targetPort: port, originatorAddress: origin)) { channel in
            // The peer packet allowance includes protocol framing. A payload equal
            // to that allowance can otherwise produce an oversized encrypted packet.
            do { try channel.pipeline.syncOperations.addHandler(BoundedStreamWrites()) }
            catch { return channel.eventLoop.makeFailedFuture(error) }
            return initialize(channel)
        }
    }
}

final class BoundedStreamWrites: ChannelOutboundHandler {
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        var buffer = unwrapOutboundIn(data)
        guard buffer.readableBytes > 16384 else {
            context.write(data, promise: promise)
            return
        }
        var writes: [EventLoopFuture<Void>] = []
        while let part = buffer.readSlice(length: min(16384, buffer.readableBytes)), part.readableBytes > 0 {
            let written = context.eventLoop.makePromise(of: Void.self)
            context.write(wrapOutboundOut(part), promise: written)
            writes.append(written.futureResult)
        }
        if let promise = promise {
            EventLoopFuture.andAllSucceed(writes, on: context.eventLoop).cascade(to: promise)
        }
    }
}
