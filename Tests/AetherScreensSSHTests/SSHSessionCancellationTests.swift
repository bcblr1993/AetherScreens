import XCTest
import Crypto
import NIO
import NIOSSH
import AetherScreensSSH

final class SSHSessionCancellationTests: XCTestCase {
    func testExcessivePrivateKeyKDFIsRejectedBeforeHashingOrConnecting() async throws {
        let key = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey()).publicKey
        for rounds: UInt32 in [0, 257, .max] {
            var encoded = ByteBuffer()
            encoded.writeBytes(Array("openssh-key-v1\0".utf8))
            func field(_ bytes: [UInt8]) { encoded.writeInteger(UInt32(bytes.count)); encoded.writeBytes(bytes) }
            field(Array("aes256-ctr".utf8)); field(Array("bcrypt".utf8))
            var options = ByteBuffer(); options.writeInteger(UInt32(16))
            options.writeBytes(Array(repeating: UInt8(1), count: 16)); options.writeInteger(rounds)
            field(Array(options.readableBytesView))
            let text = "-----BEGIN OPENSSH PRIVATE KEY-----\n" + Data(encoded.readableBytesView).base64EncodedString()
                + "\n-----END OPENSSH PRIVATE KEY-----\n"
            let start = Date()
            do {
                let unexpected = try await SSHRemoteSession.connect(host: "127.0.0.1", port: 1, username: "qa-fixture",
                    credentials: .ed25519PrivateKey(text, passphrase: "synthetic-fixture-only"), trustedServerKey: key)
                try await unexpected.close()
                XCTFail("Unbounded private-key cost unexpectedly accepted")
            } catch {
                XCTAssertEqual(error as? SSHRemoteSession.ConfigurationError, .invalidPrivateKey)
            }
            XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
        }
    }

    func testCancellingSessionDuringSilentServerHandshakeClosesSocket() async throws {
        try await exerciseSilentHandshakeCancellation()
    }

    func testRepeatedCancellationDuringSilentHandshakeDoesNotLeakPromise() async throws {
        for _ in 0..<20 { try await exerciseSilentHandshakeCancellation() }
    }

    private func exerciseSilentHandshakeCancellation() async throws {
        let accepted = expectation(description: "Owned server accepted handshake socket")
        let closed = expectation(description: "Cancelled handshake closes owned TCP socket")
        let group = MultiThreadedEventLoopGroup.singleton
        let server = try await ServerBootstrap(group: group).childChannelInitializer { channel in
            accepted.fulfill()
            channel.closeFuture.whenComplete { _ in closed.fulfill() }
            return channel.eventLoop.makeSucceededVoidFuture()
        }.bind(host: "127.0.0.1", port: 0).get()
        addTeardownBlock { try? await server.close().get() }
        let key = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey()).publicKey
        let attempt = Task {
            try await SSHRemoteSession.connect(host: "127.0.0.1", port: try XCTUnwrap(server.localAddress?.port),
                username: "qa-fixture", credentials: .password("synthetic-fixture-only"), trustedServerKey: key)
        }
        await fulfillment(of: [accepted], timeout: 3)
        let started = Date()
        attempt.cancel()
        do {
            let unexpected = try await attempt.value
            try await unexpected.close()
            XCTFail("Cancelled session unexpectedly returned an open tunnel")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1, "Cancelling authentication must not wait for the login deadline")
        await fulfillment(of: [closed], timeout: 3)
    }
}
