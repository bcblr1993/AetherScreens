import XCTest
import Foundation
import Citadel
import Crypto
import NIO
import NIOSSH
import AetherScreensSSH
import AetherScreensCore

@MainActor
final class SSHSessionCoordinatorTests: XCTestCase {
    func testApplicationCloseDismissesReviewAndIgnoresStaleApproval() async throws {
        let group = MultiThreadedEventLoopGroup.singleton
        let auth = CoordinatorRejectingAuthentication()
        let privateKey = Curve25519.Signing.PrivateKey()
        let server = try await ServerBootstrap(group: group).childChannelInitializer { channel in
            do {
                try channel.pipeline.syncOperations.addHandler(NIOSSHHandler(role: .server(SSHServerConfiguration(
                    hostKeys: [NIOSSHPrivateKey(ed25519Key: privateKey)], userAuthDelegate: auth)),
                    allocator: channel.allocator, inboundChildChannelInitializer: nil))
                return channel.eventLoop.makeSucceededVoidFuture()
            } catch { return channel.eventLoop.makeFailedFuture(error) }
        }.bind(host: "127.0.0.1", port: 0).get()
        addTeardownBlock { try? await server.close().get() }
        let configuration = try SSHConfiguration(host: "127.0.0.1",
            port: UInt16(try XCTUnwrap(server.localAddress?.port)), username: "qa-fixture")
        let suite = "test.aetherscreens.ssh.application-close." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keys = TestStorage.sshKeychain()
        defer { try? keys.forgetTrustedKey(for: configuration) }
        let device = RemoteDevice(name: "Review close fixture", host: "rfb.invalid", sshConfiguration: configuration)
        let devices = TestStorage.make(userDefaults: defaults, sshKeychain: keys)
        devices.addDevice(device)
        let model = TestSession.make(device: device, password: nil, deviceStore: devices,
            sshCredentials: .password("synthetic-fixture-only"), sshKeychain: keys)
        addTeardownBlock { await MainActor.run { model.endSession() } }
        model.startSession()
        for _ in 0..<300 {
            if model.sshTrustRequest != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let review = try XCTUnwrap(model.sshTrustRequest)
        XCTAssertEqual(review.identity, SSHHostKeyIdentity(key: NIOSSHPrivateKey(ed25519Key: privateKey).publicKey))
        model.endSession()
        XCTAssertNil(model.sshTrustRequest, "Closing must dismiss the pending application trust sheet")
        model.submitSSHTrust(id: review.id, decision: .remember)
        // Let the cancelled continuation finish, then check the actual store and
        // authentication delegate rather than a displayed status string alone.
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(try keys.trustedKey(for: configuration))
        XCTAssertEqual(auth.requestCount, 0)
        XCTAssertEqual(model.client.state, .disconnected)
        model.startSession()
        XCTAssertNil(model.sshTrustRequest, "An ended session must not reopen a stale trust review")
    }

    func testStopDuringTrustReviewRejectsLateRememberWithoutAuthenticating() async throws {
        try await exerciseLateTrustDecision(cancelTask: false)
    }

    func testCancelledTrustReviewRejectsLateRememberWithoutAuthenticating() async throws {
        try await exerciseLateTrustDecision(cancelTask: true)
    }

    private func exerciseLateTrustDecision(cancelTask: Bool) async throws {
        let group = MultiThreadedEventLoopGroup.singleton
        let auth = CoordinatorRejectingAuthentication()
        let privateKey = Curve25519.Signing.PrivateKey()
        let identity = SSHHostKeyIdentity(key: NIOSSHPrivateKey(ed25519Key: privateKey).publicKey)
        let server = try await ServerBootstrap(group: group).childChannelInitializer { channel in
            do {
                try channel.pipeline.syncOperations.addHandler(NIOSSHHandler(role: .server(SSHServerConfiguration(
                    hostKeys: [NIOSSHPrivateKey(ed25519Key: privateKey)], userAuthDelegate: auth)),
                    allocator: channel.allocator, inboundChildChannelInitializer: nil))
                return channel.eventLoop.makeSucceededVoidFuture()
            } catch { return channel.eventLoop.makeFailedFuture(error) }
        }.bind(host: "127.0.0.1", port: 0).get()
        addTeardownBlock { try? await server.close().get() }
        let configuration = try SSHConfiguration(host: "127.0.0.1",
            port: UInt16(try XCTUnwrap(server.localAddress?.port)), username: "qa-fixture")
        let store = TestStorage.sshKeychain()
        defer { try? store.forgetTrustedKey(for: configuration) }
        let coordinator = SSHSessionCoordinator(store: store)
        let reviewing = expectation(description: "First-use review is awaiting user input")
        var decision: CheckedContinuation<SSHSessionCoordinator.TrustDecision, Never>?
        defer { decision?.resume(returning: .cancel) }
        let pending = Task {
            try await coordinator.connect(deviceID: UUID(), configuration: configuration,
                destinationPort: 5900, credentials: .password("synthetic-fixture-only"), temporary: false) { observed in
                XCTAssertEqual(observed, identity)
                return await withCheckedContinuation { continuation in
                    decision = continuation; reviewing.fulfill()
                }
            }
        }
        addTeardownBlock { @MainActor in pending.cancel(); await coordinator.stop().value }
        await fulfillment(of: [reviewing], timeout: 3)
        let answer = try XCTUnwrap(decision)
        let started = Date()
        if cancelTask { pending.cancel() }
        else { await coordinator.stop().value }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1, "Close must not wait for a trust dialog answer")
        answer.resume(returning: .remember); decision = nil
        do { _ = try await pending.value; XCTFail("A stale approval returned a tunnel") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(try store.trustedKey(for: configuration), "A late decision must not persist server trust")
        XCTAssertEqual(auth.requestCount, 0, "Cancelled review must never send credentials")
        // The cancelled generation must not poison a subsequent fresh review.
        var newReviews = 0
        do {
            _ = try await coordinator.connect(deviceID: UUID(), configuration: configuration,
                destinationPort: 5900, credentials: .password("synthetic-fixture-only"), temporary: false) { observed in
                XCTAssertEqual(observed, identity); newReviews += 1; return .cancel
            }
            XCTFail("A declined fresh review returned a tunnel")
        } catch {
            guard case SSHSessionCoordinator.Failure.trustCancelled = error else { throw error }
        }
        XCTAssertEqual(newReviews, 1)
        XCTAssertEqual(auth.requestCount, 0)
        await coordinator.stop().value
    }

    func testForgottenPinRequiresFreshReviewOnNextRealSSHConnection() async throws {
        let group = MultiThreadedEventLoopGroup.singleton
        let reservation = try await ServerBootstrap(group: group).bind(host: "127.0.0.1", port: 0).get()
        let port = try XCTUnwrap(reservation.localAddress?.port)
        try await reservation.close().get()
        let hostKey = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey())
        let server = try await SSHServer.host(host: "127.0.0.1", port: port, hostKeys: [hostKey],
            authenticationDelegate: FixtureAuthentication(acceptedKey: nil), group: group)
        addTeardownBlock { try? await server.close() }
        let store = TestStorage.sshKeychain()
        let configuration = try SSHConfiguration(host: "127.0.0.1", port: UInt16(port), username: "qa-fixture")
        let identity = SSHHostKeyIdentity(key: hostKey.publicKey)
        defer { try? store.forgetTrustedKey(for: configuration) }
        try store.approve(identity, for: configuration)
        let coordinator = SSHSessionCoordinator(store: store)
        var reviews = 0
        _ = try await coordinator.connect(deviceID: UUID(), configuration: configuration,
            destinationPort: 5900, credentials: .password("synthetic-fixture-only"), temporary: false) { _ in
                reviews += 1; return .cancel
            }
        XCTAssertEqual(reviews, 0)
        try store.forgetTrustedKey(for: configuration, matching: identity)
        await coordinator.stop().value
        do {
            _ = try await coordinator.connect(deviceID: UUID(), configuration: configuration,
                destinationPort: 5900, credentials: .password("synthetic-fixture-only"), temporary: false) { received in
                    reviews += 1; XCTAssertEqual(received, identity); return .cancel
                }
            XCTFail("A cancelled fresh review must not return a tunnel")
        } catch {
            guard case SSHSessionCoordinator.Failure.trustCancelled = error else { throw error }
        }
        XCTAssertEqual(reviews, 1)
        XCTAssertNil(try store.trustedKey(for: configuration))
        await coordinator.stop().value
    }

    func testEditedSSHConfigurationDoesNotReuseAnOldRetainedSession() throws {
        let registry = SessionRegistry()
        var device = RemoteDevice(name: "Retained fixture", host: "rfb.invalid")
        let original = TestSession.make(device: device, password: nil, isTemporary: true)
        let first = registry.register(original)
        device.sshConfiguration = try SSHConfiguration(host: "ssh.invalid", username: "qa")
        let edited = TestSession.make(device: device, password: nil, isTemporary: true)
        let second = registry.register(edited)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(registry.sessions.count, 2)
        XCTAssertEqual(registry.register(TestSession.make(device: device, password: nil, isTemporary: true)), second)
        registry.close(first); registry.close(second)
    }
    func testRejectingFirstUseDoesNotPersistTrustOrCreateTunnel() async throws {
        try await exerciseTrust(decision: .cancel)
    }
    func testTrustOnceConnectsWithoutPersistingPinAndStopClosesListener() async throws {
        try await exerciseTrust(decision: .once)
    }
    func testRememberedTrustIsDurableAndStopClosesListener() async throws {
        try await exerciseTrust(decision: .remember)
    }

    private func exerciseTrust(decision: SSHSessionCoordinator.TrustDecision) async throws {
        let group = MultiThreadedEventLoopGroup.singleton
        let reservation = try await ServerBootstrap(group: group).bind(host: "127.0.0.1", port: 0).get()
        let port = try XCTUnwrap(reservation.localAddress?.port)
        try await reservation.close().get()
        let hostKey = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey())
        let server = try await SSHServer.host(host: "127.0.0.1", port: port, hostKeys: [hostKey],
            authenticationDelegate: FixtureAuthentication(acceptedKey: nil), group: group)
        addTeardownBlock { try? await server.close() }
        let store = TestStorage.sshKeychain()
        let configuration = try SSHConfiguration(host: "127.0.0.1", port: UInt16(port), username: "qa-fixture")
        defer { try? store.forgetTrustedKey(for: configuration) }
        let coordinator = SSHSessionCoordinator(store: store)
        var reviewCount = 0
        do {
            let tunnel = try await coordinator.connect(deviceID: UUID(), configuration: configuration,
                destinationPort: 5900, credentials: .password("synthetic-fixture-only"), temporary: false) { identity in
                    reviewCount += 1
                    XCTAssertEqual(identity, SSHHostKeyIdentity(key: hostKey.publicKey))
                    return decision
                }
            XCTAssertEqual(reviewCount, 1)
            if case .cancel = decision { XCTFail("Rejected server returned a tunnel") }
            if case .remember = decision {
                XCTAssertEqual(try store.trustedKey(for: configuration), SSHHostKeyIdentity(key: hostKey.publicKey))
            } else { XCTAssertNil(try store.trustedKey(for: configuration)) }
            await coordinator.stop().value
            do {
                let unexpected = try await ClientBootstrap(group: group).connectTimeout(.seconds(1))
                    .connect(host: "127.0.0.1", port: tunnel.port).get()
                try await unexpected.close().get()
                XCTFail("Stopped coordinator left a listener open")
            } catch { }
        } catch {
            guard case .cancel = decision else { throw error }
            guard case SSHSessionCoordinator.Failure.trustCancelled = error else { throw error }
            XCTAssertEqual(reviewCount, 1)
            XCTAssertNil(try store.trustedKey(for: configuration))
            await coordinator.stop().value
        }
    }

    func testStopDuringSilentProbeCancelsOwnedSocketImmediately() async throws {
        let accepted = expectation(description: "Probe socket accepted")
        let closed = expectation(description: "Stop closes pending probe")
        let server = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton).childChannelInitializer { channel in
            accepted.fulfill(); channel.closeFuture.whenComplete { _ in closed.fulfill() }
            return channel.eventLoop.makeSucceededVoidFuture()
        }.bind(host: "127.0.0.1", port: 0).get()
        addTeardownBlock { try? await server.close().get() }
        let configuration = try SSHConfiguration(host: "127.0.0.1", port: UInt16(try XCTUnwrap(server.localAddress?.port)), username: "qa-fixture")
        let coordinator = SSHSessionCoordinator(store: TestStorage.sshKeychain())
        let pending = Task {
            try await coordinator.connect(deviceID: UUID(), configuration: configuration,
                destinationPort: 5900, credentials: .password("synthetic-fixture-only"), temporary: true) { _ in
                    XCTFail("Silent server cannot produce a trust prompt"); return .cancel
                }
        }
        await fulfillment(of: [accepted], timeout: 3)
        let started = Date()
        await coordinator.stop().value
        do { _ = try await pending.value; XCTFail("Stopped probe returned a tunnel") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
        await fulfillment(of: [closed], timeout: 3)
    }
}

private final class CoordinatorRejectingAuthentication: NIOSSHServerUserAuthenticationDelegate, @unchecked Sendable {
    let supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods = [.password]
    private let lock = NSLock()
    private var count = 0
    var requestCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    func requestReceived(request: NIOSSHUserAuthenticationRequest,
                         responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
        lock.lock(); count += 1; lock.unlock()
        responsePromise.succeed(.failure)
    }
}
