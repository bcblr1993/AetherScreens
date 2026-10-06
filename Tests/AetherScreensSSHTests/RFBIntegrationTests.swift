import XCTest
import Foundation
import Crypto
import Citadel
import NIO
import NIOSSH
import AetherScreensSSH
@testable import AetherScreensCore

final class RFBIntegrationTests: XCTestCase {
    func testRFBHandshakeFrameAndInputUseAuthenticatedEncryptedTunnel() async throws {
        try await exerciseRFB()
    }
    func testFinalLockTransactionReachesRFBServerBeforeTunnelCloses() async throws {
        try await exerciseRFB(finalAction: true)
    }
    func testOwnedSessionRejectsChangedPinnedHostDuringHandshake() async throws {
        try await exerciseRFB(wrongHost: true)
    }
    func testApplicationSessionOwnsSSHAndDeliversFinalLockBeforeClose() async throws {
        try await exerciseRFB(finalAction: true, applicationSession: true)
    }
    func testApplicationBackgroundClosesRFBAndOwnedSSHSocketWithoutFinalLockOrAutomaticReconnect() async throws {
        try await exerciseRFB(applicationSession: true, backgroundApplication: true)
    }
    func testRepeatedImmediateSSHHandshakesPreserveRFBFramesAndInputs() async throws {
        for _ in 0..<10 { try await exerciseRFB() }
    }
    func testExternalSSHTunnelDoesNotMisclassifyLocalRFBAdapterAsRemoteHost() async throws {
        try await exerciseRFB(externalClient: true)
    }
    private func exerciseRFB(finalAction: Bool = false, wrongHost: Bool = false,
                             applicationSession: Bool = false, externalClient: Bool = false,
                             backgroundApplication: Bool = false) async throws {
        let group = MultiThreadedEventLoopGroup.singleton
        // A rejected host never opens an RFB channel; only positive cases
        // register application-input expectations with XCTest.
        let keys = wrongHost ? XCTestExpectation(description: "Rejected host must not open RFB")
            : expectation(description: "Exact Tab down/up reach remote RFB server")
        let pointers = wrongHost ? XCTestExpectation(description: "Rejected host must not deliver pointer input")
            : expectation(description: "Exact mouse down/up reach remote RFB server")
        let final = finalAction ? expectation(description: "Balanced final lock shortcut arrives before close") : nil
        let backgroundClose = backgroundApplication ? expectation(description: "Remote RFB channel closes without a lock transaction") : nil
        let center = applicationSession ? expectation(description: "Application initializes cursor at framebuffer center") : nil
        let rfbServer = try await ServerBootstrap(group: group).childChannelInitializer { channel in
            do {
                try channel.pipeline.syncOperations.addHandler(EncryptedRFBFixture(keys: keys, pointers: pointers,
                    final: final, center: center, backgroundClose: backgroundClose))
                return channel.eventLoop.makeSucceededFuture(())
            } catch { return channel.eventLoop.makeFailedFuture(error) }
        }.bind(host: "127.0.0.1", port: 0).get()
        addTeardownBlock { try? await rfbServer.close().get() }
        let rfbPort = try XCTUnwrap(rfbServer.localAddress?.port)
        let reservation = try await ServerBootstrap(group: group).bind(host: "127.0.0.1", port: 0).get()
        let sshPort = try XCTUnwrap(reservation.localAddress?.port)
        try await reservation.close().get()
        let hostKey = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey())
        let sshServer = try await SSHServer.host(host: "127.0.0.1", port: sshPort, hostKeys: [hostKey],
            authenticationDelegate: FixtureAuthentication(acceptedKey: nil), group: group)
        addTeardownBlock { try? await sshServer.close() }
        sshServer.enableDirectTCPIP(withDelegate: FixtureForwarding(port: rfbPort))
        let sshSockets = SSHSocketEvidence()
        var observedSSHPort = sshPort
        if backgroundApplication {
            // Forward encrypted bytes unchanged. The accepted parent socket's
            // closeFuture proves SSH ownership ended, independently of UI state
            // and independently of the RFB forwarding channel closing.
            let proxy = try await ServerBootstrap(group: group).childChannelInitializer { channel in
                sshSockets.accepted()
                channel.closeFuture.whenComplete { _ in sshSockets.closed() }
                return ClientBootstrap(group: channel.eventLoop).connect(host: "127.0.0.1", port: sshPort).flatMap { upstream in
                    channel.pipeline.addHandler(EncryptedSocketRelay(peer: upstream)).flatMap {
                        upstream.pipeline.addHandler(EncryptedSocketRelay(peer: channel))
                    }
                }
            }.bind(host: "127.0.0.1", port: 0).get()
            addTeardownBlock { try? await proxy.close().get() }
            observedSSHPort = try XCTUnwrap(proxy.localAddress?.port)
        }
        if wrongHost {
            do {
                let unexpected = try await SSHRemoteSession.connect(host: "127.0.0.1", port: sshPort,
                    username: "qa-fixture", credentials: .password("synthetic-fixture-only"),
                    trustedServerKey: NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey()).publicKey,
                    destinationPort: rfbPort)
                try await unexpected.close()
                XCTFail("Owned SSH session accepted changed host key")
            } catch { XCTAssertTrue(error is InvalidHostKey) }
            return
        }
        let secureSession: SSHRemoteSession?
        var externalTunnel: SSHLoopbackTunnel?
        let model: SessionViewModel?
        if applicationSession {
            let store = TestStorage.sshKeychain()
            let configuration = try SSHConfiguration(host: "127.0.0.1", port: UInt16(observedSSHPort), username: "qa-fixture")
            try store.approve(SSHHostKeyIdentity(key: hostKey.publicKey), for: configuration)
            addTeardownBlock { try? store.forgetTrustedKey(for: configuration) }
            model = await MainActor.run {
                let device = RemoteDevice(name: "Encrypted session fixture", host: "encrypted-rfb-fixture.invalid",
                    port: UInt16(rfbPort), authMethod: .none, disconnectAction: .lockScreen,
                    sshConfiguration: configuration)
                return TestSession.make(device: device, password: nil, isTemporary: true,
                    sshCredentials: .password("synthetic-fixture-only"), sshKeychain: store)
            }
            secureSession = nil
            if let model { addTeardownBlock { await MainActor.run { model.endSession() } } }
        } else if externalClient {
            model = nil
            secureSession = nil
            let settings = SSHClientSettings(host: "127.0.0.1", port: sshPort,
                authenticationMethod: { .passwordBased(username: "qa-fixture", password: "synthetic-fixture-only") },
                hostKeyValidator: HostKeyPin.validator(for: hostKey.publicKey))
            let client = try await SSHClient.connect(to: settings)
            addTeardownBlock { try? await client.close() }
            let tunnel = try await SSHLoopbackTunnel.start(client: client,
                destinationHost: "127.0.0.1", destinationPort: rfbPort)
            externalTunnel = tunnel
            addTeardownBlock { try? await tunnel.stop() }
        } else {
            model = nil
            let opened = try await SSHRemoteSession.connect(host: "127.0.0.1", port: sshPort,
                username: "qa-fixture", credentials: .password("synthetic-fixture-only"),
                trustedServerKey: hostKey.publicKey, destinationPort: rfbPort)
            secureSession = opened
            addTeardownBlock { try? await opened.close() }
        }
        // This logical remote name cannot resolve. The test cannot accidentally
        // pass by connecting directly to the fixture instead of the SSH tunnel.
        let rfb: RFBClient
        if let model { rfb = await MainActor.run { model.client } }
        else { rfb = RFBClient(host: "encrypted-rfb-fixture.invalid", port: UInt16(rfbPort), automaticClipboard: false) }
        addTeardownBlock { rfb.disconnect() }
        let connected = expectation(description: "RFB handshake through SSH")
        let frame = expectation(description: "Remote framebuffer through SSH")
        let stateCallback = rfb.onStateChanged
        let frameCallback = rfb.onFrameUpdated
        rfb.onStateChanged = { stateCallback?($0); if $0 == .connected { connected.fulfill() } }
        rfb.onFrameUpdated = { frameCallback?(); frame.fulfill() }
        if let model { await MainActor.run { model.startSession() } }
        else if let secureSession { rfb.connect(using: secureSession.tunnel) }
        else if let externalTunnel { rfb.connect(using: externalTunnel) }
        await fulfillment(of: [connected, frame], timeout: 5)
        if let center { await fulfillment(of: [center], timeout: 3) }
        XCTAssertEqual(rfb.state, .connected)
        if externalClient {
            XCTAssertNil(rfb.isLocalConnection, "Unknown SSH metadata must not fall back to the loopback adapter")
        } else {
            XCTAssertEqual(rfb.isLocalConnection, true, "Classify the authenticated socket, not the adapter")
        }
        if let secureSession {
            XCTAssertEqual(secureSession.tunnel.transportEndpoints?.destinationIsSSHHost, true)
            XCTAssertEqual(secureSession.tunnel.transportEndpoints?.remoteAddress, Data([127, 0, 0, 1]))
        }
        XCTAssertEqual(rfb.host, "encrypted-rfb-fixture.invalid")
        XCTAssertEqual(rfb.port, UInt16(rfbPort))
        XCTAssertEqual(rfb.framebuffer.width, 16)
        XCTAssertEqual(rfb.framebuffer.height, 16)
        XCTAssertEqual(Array(rfb.framebuffer.pixels.prefix(4)), [80, 120, 200, 255])
        if let model {
            for _ in 0..<100 {
                if await MainActor.run(body: { model.hasReceivedFirstFrame && model.sessionState == .connected }) { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            // Match real UI input ordering after the first frame/cursor setup.
            await MainActor.run {
                XCTAssertTrue(model.hasReceivedFirstFrame)
                rfb.sendKeyEvent(down: true, keySym: 65289)
                rfb.sendKeyEvent(down: false, keySym: 65289)
                rfb.sendPointerEvent(buttonMask: .left, x: 5, y: 6)
                rfb.sendPointerEvent(buttonMask: [], x: 5, y: 6)
            }
        } else {
            rfb.sendKeyEvent(down: true, keySym: 65289)
            rfb.sendKeyEvent(down: false, keySym: 65289)
            rfb.sendPointerEvent(buttonMask: .left, x: 5, y: 6)
            rfb.sendPointerEvent(buttonMask: [], x: 5, y: 6)
        }
        await fulfillment(of: [keys, pointers], timeout: 3)
        if backgroundApplication, let model, let backgroundClose {
            await MainActor.run {
                model.zoomScale = 2.5
                model.viewOffset = CGSize(width: 11, height: -7)
                model.enterApplicationBackground()
            }
            await fulfillment(of: [backgroundClose], timeout: 3)
            for _ in 0..<300 {
                if sshSockets.counts.closed == 1 { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTAssertEqual(sshSockets.counts.accepted, 1)
            XCTAssertEqual(sshSockets.counts.closed, 1, "Backgrounding must close the authenticated SSH parent socket")
            await MainActor.run {
                XCTAssertTrue(model.hasReceivedFirstFrame)
                XCTAssertEqual(model.zoomScale, 2.5)
                XCTAssertEqual(model.viewOffset, CGSize(width: 11, height: -7))
                model.startSession()
                XCTAssertEqual(model.client.state, .disconnected, "An explicit start while backgrounded must not open RFB or SSH")
                model.setApplicationInputActive(true)
                model.setClipboardApplicationActive(true)
                model.setForegroundSession(true)
            }
            try await Task.sleep(nanoseconds: 200_000_000)
            XCTAssertEqual(sshSockets.counts.accepted, 1, "Returning to foreground must not open another SSH socket")
            await MainActor.run { XCTAssertEqual(model.sessionState, .disconnected) }
        } else if let final = final {
            if let model {
                await MainActor.run { model.endSession() }
                await fulfillment(of: [final], timeout: 3)
            } else {
                let sent = expectation(description: "Final TCP transaction processed")
                rfb.disconnect(after: .lockScreen) { success in XCTAssertTrue(success); sent.fulfill() }
                await fulfillment(of: [sent, final], timeout: 3)
            }
        } else { rfb.disconnect() }
        if let secureSession { try await secureSession.close(); try await secureSession.close() }
        for _ in 0..<100 {
            if rfb.state == .disconnected { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(rfb.state, .disconnected)
        XCTAssertNil(rfb.isLocalConnection, "A closed connection must not keep a stale route")
    }
}

/// Independent minimal RFB 3.8 server with fixed wire packets. All state is
/// confined to its channel's event loop. Unexpected input fails the connection.
private final class EncryptedRFBFixture: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    enum Stage { case version, security, shared, messages }
    var stage = Stage.version
    var buffer: ByteBuffer?
    var sentFrame = false
    var keys: [[UInt8]] = []
    var pointers: [[UInt8]] = []
    let keyReceipt: XCTestExpectation
    let pointerReceipt: XCTestExpectation
    let finalReceipt: XCTestExpectation?
    var centerReceipt: XCTestExpectation?
    let backgroundCloseReceipt: XCTestExpectation?
    init(keys: XCTestExpectation, pointers: XCTestExpectation, final: XCTestExpectation?, center: XCTestExpectation? = nil,
         backgroundClose: XCTestExpectation? = nil) {
        keyReceipt = keys; pointerReceipt = pointers; finalReceipt = final
        centerReceipt = center
        backgroundCloseReceipt = backgroundClose
    }
    func channelInactive(context: ChannelHandlerContext) {
        if let backgroundCloseReceipt {
            XCTAssertEqual(keys.count, 2, "A saved lock preference must not emit any extra keys during backgrounding")
            XCTAssertEqual(pointers.count, 2)
            backgroundCloseReceipt.fulfill()
        }
        context.fireChannelInactive()
    }
    func channelActive(context: ChannelHandlerContext) {
        send(Array("RFB 003.008\n".utf8), context)
        context.fireChannelActive()
    }
    func send(_ bytes: [UInt8], _ context: ChannelHandlerContext) {
        var packet = context.channel.allocator.buffer(capacity: bytes.count)
        packet.writeBytes(bytes)
        context.writeAndFlush(NIOAny(packet), promise: nil)
    }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var incoming = unwrapInboundIn(data)
        if buffer == nil { buffer = context.channel.allocator.buffer(capacity: 256) }
        buffer?.writeBuffer(&incoming)
        while var pending = buffer {
            let needed: Int
            switch stage {
            case .version: needed = 12
            case .security, .shared: needed = 1
            case .messages:
                guard let kind: UInt8 = pending.getInteger(at: pending.readerIndex) else { return }
                switch kind {
                case 0: needed = 20
                case 2:
                    guard let count: UInt16 = pending.getInteger(at: pending.readerIndex + 2) else { return }
                    needed = 4 + Int(count) * 4
                case 3: needed = 10
                case 4: needed = 8
                case 5: needed = 6
                default: XCTFail("Unexpected client message in encrypted RFB fixture"); context.close(promise: nil); return
                }
            }
            guard let bytes = pending.readBytes(length: needed) else { return }
            buffer = pending
            switch stage {
            case .version:
                XCTAssertEqual(bytes, Array("RFB 003.008\n".utf8)); stage = .security
                send([1, 1], context)
            case .security:
                XCTAssertEqual(bytes, [1]); stage = .shared; send([0, 0, 0, 0], context)
            case .shared:
                XCTAssertEqual(bytes, [1]); stage = .messages
                let pixelFormat: [UInt8] = [32, 24, 0, 1, 0, 255, 0, 255, 0, 255, 16, 8, 0, 0, 0, 0]
                send([0, 16, 0, 16] + pixelFormat + [0, 0, 0, 2, 81, 65], context)
            case .messages:
                if bytes[0] == 3 && !sentFrame {
                    sentFrame = true
                    send([0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 80, 120, 200, 255], context)
                } else if bytes[0] == 4 {
                    keys.append(bytes)
                    if keys.count == 2 {
                        XCTAssertEqual(keys, [[4, 1, 0, 0, 0, 0, 255, 9], [4, 0, 0, 0, 0, 0, 255, 9]])
                        keyReceipt.fulfill()
                    } else if keys.count == 8 && finalReceipt != nil {
                        let finalBytes = keys.dropFirst(2).flatMap { $0 }
                        let expected: [[UInt8]] = [
                            [4, 1, 0, 0, 0, 0, 255, 227], [4, 1, 0, 0, 0, 0, 255, 235],
                            [4, 1, 0, 0, 0, 0, 0, 113], [4, 0, 0, 0, 0, 0, 0, 113],
                            [4, 0, 0, 0, 0, 0, 255, 235], [4, 0, 0, 0, 0, 0, 255, 227]
                        ]
                        XCTAssertEqual(finalBytes, expected.flatMap { $0 })
                        finalReceipt?.fulfill()
                    }
                } else if bytes[0] == 5 {
                    if let center = centerReceipt, pointers.isEmpty {
                        XCTAssertEqual(bytes, [5, 0, 0, 8, 0, 8])
                        centerReceipt = nil; center.fulfill()
                        continue
                    }
                    pointers.append(bytes)
                    if pointers.count == 2 {
                        XCTAssertEqual(pointers, [[5, 1, 0, 5, 0, 6], [5, 0, 0, 5, 0, 6]])
                        pointerReceipt.fulfill()
                    }
                }
            }
        }
    }
}

private final class SSHSocketEvidence: @unchecked Sendable {
    private let lock = NSLock()
    private var acceptedCount = 0
    private var closedCount = 0
    func accepted() { lock.lock(); acceptedCount += 1; lock.unlock() }
    func closed() { lock.lock(); closedCount += 1; lock.unlock() }
    var counts: (accepted: Int, closed: Int) {
        lock.lock(); defer { lock.unlock() }; return (acceptedCount, closedCount)
    }
}

private final class EncryptedSocketRelay: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    let peer: Channel
    init(peer: Channel) { self.peer = peer }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        peer.writeAndFlush(unwrapInboundIn(data), promise: nil)
    }
    func channelInactive(context: ChannelHandlerContext) {
        peer.close(promise: nil)
        context.fireChannelInactive()
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        peer.close(promise: nil)
        context.close(promise: nil)
    }
}
