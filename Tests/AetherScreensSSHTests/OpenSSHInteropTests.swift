import XCTest
import Foundation
import Crypto
import Citadel
import NIO
import NIOSSH
import AetherScreensSSH

final class OpenSSHInteropTests: XCTestCase {
    func testPinnedEd25519ForwardingThroughSystemOpenSSH() async throws {
        let group = MultiThreadedEventLoopGroup.singleton
        let echo = try await ServerBootstrap(group: group)
            .childChannelInitializer { channel in
                do { try channel.pipeline.syncOperations.addHandler(InteropEcho()); return channel.eventLoop.makeSucceededFuture(()) }
                catch { return channel.eventLoop.makeFailedFuture(error) }
            }.bind(host: "127.0.0.1", port: 0).get()
        addTeardownBlock { try? await echo.close().get() }
        let echoPort = try XCTUnwrap(echo.localAddress?.port)
        let reservation = try await ServerBootstrap(group: group).bind(host: "127.0.0.1", port: 0).get()
        let port = try XCTUnwrap(reservation.localAddress?.port)
        try await reservation.close().get()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aetherscreens-ssh-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        func generate(_ name: String, passphrase: String = "") throws -> Curve25519.Signing.PrivateKey {
            let key = directory.appendingPathComponent(name)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
            process.arguments = ["-q", "-t", "ed25519", "-N", passphrase, "-C", "qa-fixture", "-f", key.path]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            return try Curve25519.Signing.PrivateKey(sshEd25519: String(contentsOf: key, encoding: .utf8),
                decryptionKey: passphrase.isEmpty ? nil : Data(passphrase.utf8))
        }
        let hostKey = try generate("host-key")
        let fingerprintProcess = Process()
        fingerprintProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        fingerprintProcess.arguments = ["-l", "-E", "sha256", "-f", directory.appendingPathComponent("host-key.pub").path]
        let fingerprintPipe = Pipe()
        fingerprintProcess.standardOutput = fingerprintPipe; fingerprintProcess.standardError = FileHandle.nullDevice
        try fingerprintProcess.run()
        let fingerprintOutput = fingerprintPipe.fileHandleForReading.readDataToEndOfFile()
        fingerprintProcess.waitUntilExit()
        XCTAssertEqual(fingerprintProcess.terminationStatus, 0)
        let expectedFingerprint = try XCTUnwrap(String(data: fingerprintOutput, encoding: .utf8)?.split(separator: " ").dropFirst().first)
        let identity = SSHHostKeyIdentity(key: NIOSSHPrivateKey(ed25519Key: hostKey).publicKey)
        XCTAssertEqual(identity.fingerprint, String(expectedFingerprint))
        XCTAssertEqual(try NIOSSHPublicKey(openSSHPublicKey: identity.openSSHKey), NIOSSHPrivateKey(ed25519Key: hostKey).publicKey)
        _ = try generate("client-key", passphrase: "synthetic-session-passphrase")
        let configuration = directory.appendingPathComponent("sshd_config")
        let text = """
        Port \(port)
        ListenAddress 127.0.0.1
        HostKey \(directory.appendingPathComponent("host-key").path)
        PidFile \(directory.appendingPathComponent("sshd.pid").path)
        AuthorizedKeysFile \(directory.appendingPathComponent("client-key.pub").path)
        StrictModes yes
        PasswordAuthentication no
        KbdInteractiveAuthentication no
        UsePAM no
        AllowUsers \(NSUserName())
        AuthenticationMethods publickey
        AllowTcpForwarding local
        PermitOpen 127.0.0.1:\(echoPort)
        ForceCommand /usr/bin/false
        LogLevel ERROR
        """
        try text.write(to: configuration, atomically: true, encoding: .utf8)
        let log = directory.appendingPathComponent("sshd.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: log)
        defer { try? logHandle.close() }
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/sbin/sshd")
        server.arguments = ["-D", "-e", "-f", configuration.path]
        server.standardInput = FileHandle.nullDevice; server.standardOutput = logHandle; server.standardError = logHandle
        try server.run()
        defer { if server.isRunning { server.terminate(); server.waitUntilExit() } }
        var ready = false
        for _ in 0..<30 {
            guard server.isRunning else { throw InteropFailure.serverStartup }
            do {
                let socket = try await ClientBootstrap(group: group).connectTimeout(.milliseconds(100)).connect(host: "127.0.0.1", port: port).get()
                try await socket.close().get(); ready = true; break
            } catch { try await Task.sleep(nanoseconds: 100_000_000) }
        }
        XCTAssertTrue(ready)
        guard ready else { throw InteropFailure.serverStartup }
        let privateKeyText = try String(contentsOf: directory.appendingPathComponent("client-key"), encoding: .utf8)
        let session = try await SSHRemoteSession.connect(host: "127.0.0.1", port: port, username: NSUserName(),
            credentials: .ed25519PrivateKey(privateKeyText, passphrase: "synthetic-session-passphrase"),
            trustedServerKey: NIOSSHPrivateKey(ed25519Key: hostKey).publicKey, destinationPort: echoPort)
        addTeardownBlock { try? await session.close() }
        let payload = Array((0..<262144).map { UInt8(truncatingIfNeeded: $0) })
        let result = group.next().makePromise(of: [UInt8].self)
        let channel = try await ClientBootstrap(group: group).connectTimeout(.seconds(3)).channelInitializer { channel in
            do { try channel.pipeline.syncOperations.addHandler(InteropReply(count: payload.count, result: result)); return channel.eventLoop.makeSucceededFuture(()) }
            catch { return channel.eventLoop.makeFailedFuture(error) }
        }.connect(host: "127.0.0.1", port: session.tunnel.port).get()
        addTeardownBlock { try? await channel.close().get() }
        var buffer = channel.allocator.buffer(capacity: payload.count); buffer.writeBytes(payload)
        try await channel.writeAndFlush(buffer).get()
        let received = try await result.futureResult.get()
        XCTAssertEqual(received, payload)
        try await channel.close().get(); try await session.close()
        XCTAssertFalse(channel.isActive)
    }
}

private enum InteropFailure: Error { case serverStartup, truncated, timeout }
private final class InteropEcho: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    func channelRead(context: ChannelHandlerContext, data: NIOAny) { context.writeAndFlush(data, promise: nil) }
}
private final class InteropReply: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    let count: Int
    let result: EventLoopPromise<[UInt8]>
    var bytes: [UInt8] = []
    var done = false
    var timeout: Scheduled<Void>?
    init(count: Int, result: EventLoopPromise<[UInt8]>) { self.count = count; self.result = result }
    func handlerAdded(context: ChannelHandlerContext) {
        timeout = context.eventLoop.scheduleTask(in: .seconds(5)) { [self] in
            if !done { done = true; result.fail(InteropFailure.timeout) }
        }
    }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !done else { return }
        bytes.append(contentsOf: unwrapInboundIn(data).readableBytesView)
        if bytes.count >= count { done = true; timeout?.cancel(); result.succeed(bytes) }
    }
    func channelInactive(context: ChannelHandlerContext) {
        if !done { done = true; timeout?.cancel(); result.fail(InteropFailure.truncated) }
        context.fireChannelInactive()
    }
}
