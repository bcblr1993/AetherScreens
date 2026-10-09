import XCTest
import NIOCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@testable import AetherScreensCore

final class SessionReconnectPolicyTests: XCTestCase {
    func testSocketRetryMappingRejectsPermissionsAuthenticationAndProtocolFailures() {
        XCTAssertTrue(SessionReconnectPolicy.retriesSSHError(IOError(errnoCode: ECONNREFUSED, reason: "QA refusal")))
        XCTAssertTrue(SessionReconnectPolicy.retriesSSHError(ChannelError.connectTimeout(.seconds(1))))
        XCTAssertTrue(SessionReconnectPolicy.retriesSSHError(ChannelError.eof))
        for error: Error in [IOError(errnoCode: EACCES, reason: "QA permission"),
            IOError(errnoCode: EINVAL, reason: "QA invalid argument"), ChannelError.operationUnsupported,
            SSHForwardingTunnel.Failure.authenticationFailed, SSHForwardingTunnel.Failure.hostKeyRejected,
            SSHForwardingTunnel.Failure.invalidData, CancellationError()] {
            XCTAssertFalse(SessionReconnectPolicy.retriesSSHError(error))
        }
    }

    func testSSHRetryClassificationRejectsCredentialTrustAndUnknownFailures() {
        XCTAssertTrue(SessionReconnectPolicy.retriesSSHFailure(.closed))
        XCTAssertTrue(SessionReconnectPolicy.retriesSSHFailure(.timedOut))
        for failure: SSHForwardingTunnel.Failure? in [nil, .cancelled, .authenticationFailed,
            .hostKeyRejected, .unsupportedAuthentication, .invalidForward, .invalidData] {
            XCTAssertFalse(SessionReconnectPolicy.retriesSSHFailure(failure))
        }
    }

    func testInitialFailuresDoNotRetryAndEstablishedSessionHasFiniteBackoff() {
        var policy = SessionReconnectPolicy()
        XCTAssertNil(policy.nextDelay())
        policy.receivedDesktop()
        XCTAssertEqual((0..<5).compactMap { _ in policy.nextDelay() }, [1, 2, 4, 8, 16])
        XCTAssertNil(policy.nextDelay())
        policy.receivedDesktop()
        XCTAssertEqual(policy.nextDelay(), 1)
    }

    func testExplicitStopCannotBeRearmedByLateFrame() {
        var policy = SessionReconnectPolicy()
        policy.receivedDesktop()
        XCTAssertEqual(policy.nextDelay(), 1)
        policy.stop()
        policy.receivedDesktop()
        XCTAssertNil(policy.nextDelay())
    }
}
