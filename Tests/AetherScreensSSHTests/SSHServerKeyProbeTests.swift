import XCTest
import Foundation
import Citadel
import Crypto
import NIO
import NIOSSH
import AetherScreensSSH

final class SSHServerKeyProbeTests: XCTestCase {
    func testInspectReturnsPublicIdentityWithoutSendingAuthentication() async throws {
        try await exerciseProbe(connections: 1)
    }
    func testImmediateServerBannersSurviveRepeatedConnectionSetup() async throws {
        try await exerciseProbe(connections: 20)
    }
    private func exerciseProbe(connections: Int) async throws {
        let group = MultiThreadedEventLoopGroup.singleton
        let privateKey = Curve25519.Signing.PrivateKey()
        let hostKey = NIOSSHPrivateKey(ed25519Key: privateKey)
        let auth = RejectAllAuthentication()
        let closed = expectation(description: "Probe socket closed before returning")
        closed.expectedFulfillmentCount = connections
        let server = try await ServerBootstrap(group: group).childChannelInitializer { channel in
            channel.closeFuture.whenComplete { _ in closed.fulfill() }
            do {
                try channel.pipeline.syncOperations.addHandler(NIOSSHHandler(role: .server(SSHServerConfiguration(
                    hostKeys: [NIOSSHPrivateKey(ed25519Key: privateKey)], userAuthDelegate: auth)), allocator: channel.allocator,
                    inboundChildChannelInitializer: nil))
                return channel.eventLoop.makeSucceededVoidFuture()
            } catch { return channel.eventLoop.makeFailedFuture(error) }
        }.bind(host: "127.0.0.1", port: 0).get()
        addTeardownBlock { try? await server.close().get() }
        for _ in 0..<connections {
            let identity = try await SSHServerKeyProbe.inspect(host: "127.0.0.1", port: try XCTUnwrap(server.localAddress?.port))
            XCTAssertEqual(identity, SSHHostKeyIdentity(key: hostKey.publicKey))
        }
        await fulfillment(of: [closed], timeout: 3)
        XCTAssertEqual(auth.requestCount, 0, "First-use review must precede every authentication request")
    }

    func testCancelSilentProbeClosesSocketImmediately() async throws {
        try await exerciseEarlyCancellation()
    }

    func testRepeatedEarlyCancellationDoesNotLeakProbePromises() async throws {
        for _ in 0..<20 { try await exerciseEarlyCancellation() }
    }

    private func exerciseEarlyCancellation() async throws {
        let accepted = expectation(description: "Probe accepted")
        let closed = expectation(description: "Cancelled probe socket closed")
        let server = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .childChannelInitializer { channel in
                accepted.fulfill()
                channel.closeFuture.whenComplete { _ in closed.fulfill() }
                return channel.eventLoop.makeSucceededVoidFuture()
            }.bind(host: "127.0.0.1", port: 0).get()
        addTeardownBlock { try? await server.close().get() }
        let port = try XCTUnwrap(server.localAddress?.port)
        let attempt = Task { try await SSHServerKeyProbe.inspect(host: "127.0.0.1", port: port) }
        await fulfillment(of: [accepted], timeout: 3)
        let start = Date(); attempt.cancel()
        do { _ = try await attempt.value; XCTFail("Cancelled probe returned an identity") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
        await fulfillment(of: [closed], timeout: 3)
        try await server.close().get()
    }

    func testInvalidProbeEndpointIsRejectedBeforeConnecting() async throws {
        for host in ["", "user@host", "host/name", "host name", "host\0name"] {
            do { _ = try await SSHServerKeyProbe.inspect(host: host); XCTFail("Invalid endpoint accepted") }
            catch { XCTAssertTrue(error is SSHServerKeyProbe.Failure) }
        }
    }
}

private final class RejectAllAuthentication: NIOSSHServerUserAuthenticationDelegate, @unchecked Sendable {
    let supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods = [.password, .publicKey]
    private let lock = NSLock()
    private var count = 0
    var requestCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    func requestReceived(request: NIOSSHUserAuthenticationRequest,
                         responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
        lock.lock(); count += 1; lock.unlock()
        responsePromise.succeed(.failure)
    }
}
