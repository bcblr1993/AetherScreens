import XCTest
import Foundation
import Citadel
import Crypto
import NIO
import NIOSSH
import AetherScreensSSH

final class DirectForwardingTests: XCTestCase {
    func testEncryptedDirectTCPChannelPreservesBinaryBytesAndCloses() async throws {
        try await runTransfer()
    }

    func testEncryptedImportedEd25519KeyAuthenticatesAndForwards() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let keyPath = directory.appendingPathComponent("fixture-key")
        let generation = Process()
        generation.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        generation.arguments = ["-q", "-t", "ed25519", "-N", "synthetic-key-passphrase", "-C", "qa-fixture", "-f", keyPath.path]
        generation.standardOutput = FileHandle.nullDevice
        generation.standardError = FileHandle.nullDevice
        try generation.run()
        generation.waitUntilExit()
        XCTAssertEqual(generation.terminationStatus, 0)
        let encoded = try String(contentsOf: keyPath, encoding: .utf8)
        XCTAssertThrowsError(try Curve25519.Signing.PrivateKey(sshEd25519: encoded,
            decryptionKey: Data("wrong-fixture-passphrase".utf8)))
        let privateKey = try Curve25519.Signing.PrivateKey(sshEd25519: encoded,
            decryptionKey: Data("synthetic-key-passphrase".utf8))
        try await runTransfer(privateKey: privateKey)
    }

    func testLoopbackTunnelPreservesBytesAndStopClosesLocalSocket() async throws {
        try await runTransfer(loopback: true)
    }

    func testLoopbackTunnelResumesAfterDelayedConsumerWithoutDataLoss() async throws {
        try await runTransfer(loopback: true, pausedEcho: true, payloadSize: 4 * 1024 * 1024)
    }

    func testClosingSSHWhileLoopbackOpensClosesLocalSocket() async throws {
        try await runTransfer(loopback: true, dropSSH: true)
    }

    func testChangedHostKeyIsRejectedDuringActualHandshake() async throws {
        try await runTransfer(rejectHost: true)
    }

    private func runTransfer(privateKey: Curve25519.Signing.PrivateKey? = nil,
                             rejectHost: Bool = false, loopback: Bool = false,
                             pausedEcho: Bool = false, payloadSize: Int = 131072,
                             dropSSH: Bool = false) async throws {
        let group = MultiThreadedEventLoopGroup.singleton
        let echo = try await ServerBootstrap(group: group)
            .childChannelOption(ChannelOptions.autoRead, value: !pausedEcho)
            .childChannelInitializer { channel in
                do {
                    try channel.pipeline.syncOperations.addHandler(TCPEcho(delayed: pausedEcho))
                    return channel.eventLoop.makeSucceededFuture(())
                } catch { return channel.eventLoop.makeFailedFuture(error) }
            }
            .bind(host: "127.0.0.1", port: 0).get()
        addTeardownBlock { try? await echo.close().get() }
        let echoPort = try XCTUnwrap(echo.localAddress?.port)
        let reservation = try await ServerBootstrap(group: group).bind(host: "127.0.0.1", port: 0).get()
        let sshPort = try XCTUnwrap(reservation.localAddress?.port)
        try await reservation.close().get()
        let hostKey = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey())
        let server = try await SSHServer.host(host: "127.0.0.1", port: sshPort,
            hostKeys: [hostKey], authenticationDelegate: FixtureAuthentication(acceptedKey: privateKey.map { NIOSSHPrivateKey(ed25519Key: $0).publicKey }), group: group)
        addTeardownBlock { try? await server.close() }
        server.enableDirectTCPIP(withDelegate: FixtureForwarding(port: echoPort))
        var settings = SSHClientSettings(host: "127.0.0.1", port: sshPort,
            authenticationMethod: {
                if let privateKey = privateKey { return .ed25519(username: "qa-fixture", privateKey: privateKey) }
                return .passwordBased(username: "qa-fixture", password: "synthetic-fixture-only")
            },
            hostKeyValidator: HostKeyPin.validator(for: rejectHost
                ? NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey()).publicKey : hostKey.publicKey))
        settings.connectTimeout = .seconds(3)
        if rejectHost {
            do {
                let unexpected = try await SSHClient.connect(to: settings)
                try await unexpected.close()
                XCTFail("Unexpectedly accepted a changed server key")
            } catch {
                XCTAssertTrue(error is InvalidHostKey)
            }
            return
        }
        let client = try await SSHClient.connect(to: settings)
        addTeardownBlock { try? await client.close() }
        let payload = Array((0..<payloadSize).map { UInt8(truncatingIfNeeded: $0) })
        let reply = group.next().makePromise(of: [UInt8].self)
        let tunnel: SSHLoopbackTunnel?
        let child: Channel
        let install: @Sendable (Channel) -> EventLoopFuture<Void> = { channel in
            do {
                try channel.pipeline.syncOperations.addHandler(BinaryReply(expected: payload.count, promise: reply))
                return channel.eventLoop.makeSucceededFuture(())
            } catch { return channel.eventLoop.makeFailedFuture(error) }
        }
        if loopback {
            let started = try await SSHLoopbackTunnel.start(client: client, destinationHost: "127.0.0.1", destinationPort: echoPort)
            XCTAssertNil(started.transportEndpoints, "An external client must not invent an authenticated route")
            tunnel = started
            addTeardownBlock { try? await started.stop() }
            child = try await ClientBootstrap(group: group).connectTimeout(.seconds(3))
                .channelInitializer(install).connect(host: "127.0.0.1", port: started.port).get()
        } else {
            tunnel = nil
            child = try await SSHDirectStream.open(client: client, host: "127.0.0.1", port: echoPort, initialize: install)
        }
        addTeardownBlock { try? await child.close().get() }
        if dropSSH {
            try await client.close()
            do {
                _ = try await reply.futureResult.get()
                XCTFail("Closed SSH unexpectedly delivered a full response")
            } catch {
                XCTAssertEqual(error as? BinaryReply.Failure, .truncated)
            }
            if let tunnel = tunnel { try await tunnel.stop() }
            try await child.closeFuture.get()
            XCTAssertFalse(child.isActive)
            return
        }
        var buffer = child.allocator.buffer(capacity: payload.count)
        buffer.writeBytes(payload)
        try await child.writeAndFlush(buffer).get()
        let received = try await reply.futureResult.get()
        XCTAssertEqual(received, payload)
        if let tunnel = tunnel {
            try await tunnel.stop()
            try await child.closeFuture.get()
            do {
                let unexpected = try await ClientBootstrap(group: group).connectTimeout(.seconds(1))
                    .connect(host: "127.0.0.1", port: tunnel.port).get()
                try await unexpected.close().get()
                XCTFail("Stopped tunnel still accepts connections")
            } catch { /* An owned stopped listener must reject reconnection. */ }
        } else { try await child.close().get() }
        XCTAssertFalse(child.isActive)
        try await client.close()
    }
}

struct FixtureAuthentication: NIOSSHServerUserAuthenticationDelegate {
    let acceptedKey: NIOSSHPublicKey?
    let supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods = [.password, .publicKey]
    func requestReceived(request: NIOSSHUserAuthenticationRequest,
                         responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
        guard request.username == "qa-fixture" else { responsePromise.succeed(.failure); return }
        switch request.request {
        case .password(let password) where password.password == "synthetic-fixture-only":
            responsePromise.succeed(.success)
        case .publicKey(let key) where key.publicKey == acceptedKey:
            responsePromise.succeed(.success)
        default: responsePromise.succeed(.failure)
        }
    }
}

struct FixtureForwarding: DirectTCPIPDelegate {
    let port: Int
    enum Rejection: Error { case invalidDestination }
    func initializeDirectTCPIPChannel(_ channel: Channel, request: SSHChannelType.DirectTCPIP,
                                     context: SSHContext) -> EventLoopFuture<Void> {
        guard request.targetHost == "127.0.0.1", request.targetPort == port else {
            return channel.eventLoop.makeFailedFuture(Rejection.invalidDestination)
        }
        return ClientBootstrap(group: channel.eventLoop).connect(host: request.targetHost, port: port).flatMap { tcp in
            channel.pipeline.addHandler(SSHToTCP(remote: tcp)).flatMap {
                tcp.pipeline.addHandler(TCPToSSH(remote: channel))
            }
        }
    }
}

private final class TCPEcho: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    let delayed: Bool
    init(delayed: Bool) { self.delayed = delayed }
    func channelActive(context: ChannelHandlerContext) {
        if delayed {
            context.eventLoop.scheduleTask(in: .milliseconds(500)) {
                context.channel.setOption(ChannelOptions.autoRead, value: true).whenFailure { context.fireErrorCaught($0) }
            }
        }
        context.fireChannelActive()
    }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        context.writeAndFlush(data, promise: nil)
    }
}

private final class SSHToTCP: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    let remote: Channel
    init(remote: Channel) { self.remote = remote }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        remote.writeAndFlush(unwrapInboundIn(data), promise: nil)
    }
    func channelInactive(context: ChannelHandlerContext) { remote.close(promise: nil); context.fireChannelInactive() }
}

private final class TCPToSSH: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    weak var remote: Channel?
    init(remote: Channel) { self.remote = remote }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        remote?.writeAndFlush(unwrapInboundIn(data), promise: nil)
    }
    func channelInactive(context: ChannelHandlerContext) { remote?.close(promise: nil); context.fireChannelInactive() }
}

private final class BinaryReply: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    enum Failure: Error, Equatable { case timeout, truncated }
    let expected: Int
    let promise: EventLoopPromise<[UInt8]>
    var bytes: [UInt8] = []
    var completed = false
    var deadline: Scheduled<Void>?
    init(expected: Int, promise: EventLoopPromise<[UInt8]>) { self.expected = expected; self.promise = promise }
    func handlerAdded(context: ChannelHandlerContext) {
        deadline = context.eventLoop.scheduleTask(in: .seconds(3)) { [self] in
            if !completed { completed = true; promise.fail(Failure.timeout) }
        }
    }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !completed else { return }
        bytes.append(contentsOf: unwrapInboundIn(data).readableBytesView)
        if bytes.count >= expected { completed = true; deadline?.cancel(); promise.succeed(bytes) }
    }
    func channelInactive(context: ChannelHandlerContext) {
        if !completed { completed = true; deadline?.cancel(); promise.fail(Failure.truncated) }
        context.fireChannelInactive()
    }
}
