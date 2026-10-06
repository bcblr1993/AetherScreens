import XCTest
import Citadel
import Crypto
import NIO
import NIOSSH
import AetherScreensSSH

final class HostKeyPinTests: XCTestCase {
    func testTrustedHostKeyIsAccepted() async throws {
        let key = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey()).publicKey
        let promise = MultiThreadedEventLoopGroup.singleton.next().makePromise(of: Void.self)
        HostKeyPin.validator(for: key).validateHostKey(hostKey: key, validationCompletePromise: promise)
        try await promise.futureResult.get()
    }

    func testChangedHostKeyIsRejected() async throws {
        let trusted = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey()).publicKey
        let changed = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey()).publicKey
        let promise = MultiThreadedEventLoopGroup.singleton.next().makePromise(of: Void.self)
        HostKeyPin.validator(for: trusted).validateHostKey(hostKey: changed, validationCompletePromise: promise)
        do {
            try await promise.futureResult.get()
            XCTFail("A changed host key must not open a tunnel")
        } catch {
            XCTAssertTrue(error is InvalidHostKey)
        }
    }
}
