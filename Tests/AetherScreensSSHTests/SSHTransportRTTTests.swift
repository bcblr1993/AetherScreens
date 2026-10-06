import XCTest
import Darwin
import Citadel
import Crypto
import NIO
import NIOSSH
@testable import AetherScreensSSH

final class SSHTransportRTTTests: XCTestCase {
    func testDarwinSmoothedRTTIsMillisecondsAndZeroIsUnavailable() {
        XCTAssertNil(OwnedSSHConnection.milliseconds(smoothedRTT: 0))
        XCTAssertEqual(OwnedSSHConnection.milliseconds(smoothedRTT: 1), 1)
        XCTAssertEqual(OwnedSSHConnection.milliseconds(smoothedRTT: 23), 23)
        XCTAssertEqual(OwnedSSHConnection.milliseconds(smoothedRTT: 700), 700)
    }

    func testAuthenticatedSocketTCPInfoAndClosedSocketLifecycle() async throws {
        let (server, key) = try await makeServer()
        addTeardownBlock { try? await server.close().get() }
        let socket = try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .channelOption(ChannelOptions.autoRead, value: false)
            .connect(host: "127.0.0.1", port: try XCTUnwrap(server.localAddress?.port)).get()
        let connection = try await OwnedSSHConnection.authenticate(on: socket,
            auth: .passwordBased(username: "qa-fixture", password: "synthetic-fixture-only"), trustedKey: key)
        addTeardownBlock { try? await connection.close() }
        let info = try await connection.transportTCPInfo()
        XCTAssertGreaterThan(info.tcpi_txpackets, 0)
        XCTAssertGreaterThan(info.tcpi_rxpackets, 0)
        XCTAssertGreaterThan(info.tcpi_maxseg, 0)
        if let sample = await connection.transportRoundTripTime() {
            XCTAssertTrue(sample.isFinite)
            XCTAssertGreaterThan(sample, 0)
        }
        try await connection.close()
        XCTAssertFalse(socket.isActive)
        do { _ = try await connection.transportTCPInfo(); XCTFail("Closed socket returned TCP info") }
        catch {}
        let closed = await connection.transportRoundTripTime()
        XCTAssertNil(closed)
    }

    func testOwnedTunnelStopsReturningSSHRTTAfterListenerStop() async throws {
        let (server, key) = try await makeServer()
        addTeardownBlock { try? await server.close().get() }
        let session = try await SSHRemoteSession.connect(host: "127.0.0.1", port: try XCTUnwrap(server.localAddress?.port),
            username: "qa-fixture", credentials: .password("synthetic-fixture-only"), trustedServerKey: key)
        addTeardownBlock { try? await session.close() }
        if let sample = await session.tunnel.transportRoundTripTime() {
            XCTAssertTrue(sample.isFinite)
            XCTAssertGreaterThan(sample, 0)
        }
        try await session.tunnel.stop()
        let stopped = await session.tunnel.transportRoundTripTime()
        XCTAssertNil(stopped)
        try await session.close()
    }

    private func makeServer() async throws -> (Channel, NIOSSHPublicKey) {
        let key = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey())
        let server = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .childChannelInitializer { channel in
                do {
                    try channel.pipeline.syncOperations.addHandler(NIOSSHHandler(role: .server(
                        SSHServerConfiguration(hostKeys: [key], userAuthDelegate: FixtureAuthentication(acceptedKey: nil))),
                        allocator: channel.allocator, inboundChildChannelInitializer: nil))
                    return channel.eventLoop.makeSucceededVoidFuture()
                } catch { return channel.eventLoop.makeFailedFuture(error) }
            }.bind(host: "127.0.0.1", port: 0).get()
        return (server, key.publicKey)
    }
}
