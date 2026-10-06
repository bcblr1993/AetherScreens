import Foundation
import Citadel
import Crypto
import NIO
import NIOSSH
import AetherScreensSSH

// Local-only QA server. No shell/SFTP/exec and forwarding is restricted to the
// owned RFB fixture. Only synthetic credentials are accepted.
@main
struct SSHUIFixture {
    static func main() async throws {
        let group = MultiThreadedEventLoopGroup.singleton
        let reservation = try await ServerBootstrap(group: group).bind(host: "127.0.0.1", port: 0).get()
        guard let port = reservation.localAddress?.port else { throw RFBForwarding.Failure.destinationDenied }
        try await reservation.close().get()
        let hostKey = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey())
        let server = try await SSHServer.host(host: "127.0.0.1", port: port,
            hostKeys: [hostKey], authenticationDelegate: SyntheticAuthentication(), group: group)
        server.enableDirectTCPIP(withDelegate: RFBForwarding())
        let identity = SSHHostKeyIdentity(key: hostKey.publicKey)
        let data = try JSONSerialization.data(withJSONObject: ["port": port, "fingerprint": identity.fingerprint], options: [.sortedKeys])
        FileHandle.standardOutput.write(data + Data([10]))
        // Wrapper owns this process and terminates it after the test job closes.
        while true { try await Task.sleep(nanoseconds: 30_000_000_000) }
    }
}

private struct SyntheticAuthentication: NIOSSHServerUserAuthenticationDelegate {
    let supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods = [.password]
    func requestReceived(request: NIOSSHUserAuthenticationRequest,
                         responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
        guard request.username == "qa-fixture", case .password(let password) = request.request,
              password.password == "synthetic-fixture-only" else {
            responsePromise.succeed(.failure); return
        }
        FileHandle.standardOutput.write(Data("{\"event\":\"authenticated\"}\n".utf8))
        responsePromise.succeed(.success)
    }
}

private struct RFBForwarding: DirectTCPIPDelegate {
    enum Failure: Error { case destinationDenied }
    func initializeDirectTCPIPChannel(_ channel: Channel, request: SSHChannelType.DirectTCPIP,
                                     context: SSHContext) -> EventLoopFuture<Void> {
        guard request.targetHost == "127.0.0.1", request.targetPort == 5999 else {
            return channel.eventLoop.makeFailedFuture(Failure.destinationDenied)
        }
        return ClientBootstrap(group: channel.eventLoop).channelOption(ChannelOptions.autoRead, value: false)
            .connect(host: "127.0.0.1", port: 5999).flatMap { tcp in
                channel.pipeline.addHandler(Relay(remote: tcp)).flatMap {
                    tcp.pipeline.addHandler(Relay(remote: channel))
                }.flatMap {
                    FileHandle.standardOutput.write(Data("{\"event\":\"forward-ready\"}\n".utf8))
                    return tcp.setOption(ChannelOptions.autoRead, value: true)
                }.flatMapError { error in
                    tcp.close(promise: nil)
                    return channel.eventLoop.makeFailedFuture(error)
                }
            }
    }
}

private final class Relay: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    weak var remote: Channel?
    init(remote: Channel) { self.remote = remote }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        remote?.writeAndFlush(unwrapInboundIn(data), promise: nil)
    }
    func channelInactive(context: ChannelHandlerContext) {
        remote?.close(promise: nil); context.fireChannelInactive()
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        remote?.close(promise: nil); context.close(promise: nil)
    }
}
