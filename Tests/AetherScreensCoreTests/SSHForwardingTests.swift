import XCTest
import Network
import NIOCore
import NIOPosix
import NIOSSH
import Security
import CryptoKit
@testable import AetherScreensCore

private final class SessionSSHAccess: SSHKeychainAccess {
    var value: Data?
    var writeStatus: OSStatus = errSecSuccess
    var readStatus: OSStatus?
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        guard writeStatus == errSecSuccess else { return writeStatus }
        guard value != nil else { return errSecItemNotFound }
        value = attributes[kSecValueData as String] as? Data
        return errSecSuccess
    }
    func add(_ attributes: [String: Any]) -> OSStatus {
        guard writeStatus == errSecSuccess else { return writeStatus }
        value = attributes[kSecValueData as String] as? Data
        return errSecSuccess
    }
    func copy(_ query: [String: Any]) -> (OSStatus, Data?) { (readStatus ?? (value == nil ? errSecItemNotFound : errSecSuccess), value) }
    func delete(_ query: [String: Any]) -> OSStatus { value = nil; return errSecSuccess }
}

final class SSHForwardingTests: XCTestCase {
    @MainActor
    func testAutomaticSSHReconnectSurvivesRefusedPortThenSameIdentityReturns() async throws {
        let ready = expectation(description: "Transient SSH desktop ready")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        addTeardownBlock { server.stop() }
        await fulfillment(of: [ready], timeout: 3)
        let port = try XCTUnwrap(server.listener.port).rawValue
        let (fixture, _, trust) = try await environment(targetPort: port)
        let settings = try fixture.settings(), sshPort = fixture.sshPort
        let session = SessionViewModel(device: RemoteDevice(name: "Transient SSH QA", host: "direct-route.invalid",
            port: port, ssh: settings), password: nil, isTemporary: true,
            sshTrust: trust, initialSSHPassword: fixture.password)
        defer { session.requestDisconnect() }
        session.startSession()
        try await waitForSession { session.sshPrompt != nil }
        session.approveSSHHost(promptID: try XCTUnwrap(session.sshPrompt).id)
        try await waitForSession { session.sessionState == .connected }
        server.sendGreenFrame()
        try await waitForSession { session.hasReceivedFirstFrame }
        try await fixture.stop()
        try await Task.sleep(nanoseconds: 1_500_000_000)
        guard case .failed = session.sessionState else { return XCTFail("Unavailable SSH port must fail the first retry") }
        XCTAssertTrue(session.isAwaitingAutomaticReconnect)
        let (replacement, _, _) = try await environment(port: Int(sshPort), targetPort: port,
            hostKey: fixture.key, password: fixture.password)
        try await waitForSession { replacement.state.authCount == 1 && session.sessionState == .connected }
        XCTAssertNil(session.sshPrompt)
        server.sendGreenFrame()
        try await waitForSession { session.hasReceivedFirstFrame }
        XCTAssertEqual(replacement.state.forwardCount, 1)
        XCTAssertFalse(session.isAwaitingAutomaticReconnect)
    }

    @MainActor
    func testAutomaticReconnectRequiresChangedHostApprovalAndCancellationStopsRetries() async throws {
        let ready = expectation(description: "Changed identity desktop ready")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        addTeardownBlock { server.stop() }
        await fulfillment(of: [ready], timeout: 3)
        let port = try XCTUnwrap(server.listener.port).rawValue
        let (fixture, _, trust) = try await environment(targetPort: port)
        let settings = try fixture.settings()
        let oldKey = try fixture.identity
        let sshPort = fixture.sshPort
        let access = SessionSSHAccess()
        let session = SessionViewModel(device: RemoteDevice(name: "Changed host QA", host: "direct-route.invalid",
            port: port, ssh: settings), password: nil, isTemporary: true,
            sshCredentials: SSHCredentialStore(service: "changed-host-qa", access: access),
            sshTrust: trust, initialSSHPassword: fixture.password)
        defer { session.requestDisconnect() }
        session.startSession()
        try await waitForSession { session.sshPrompt != nil }
        session.approveSSHHost(promptID: try XCTUnwrap(session.sshPrompt).id)
        try await waitForSession { session.sessionState == .connected }
        server.sendGreenFrame()
        try await waitForSession { session.hasReceivedFirstFrame }
        try await fixture.stop()
        let (replacement, _, _) = try await environment(port: Int(sshPort), targetPort: port)
        try await waitForSession { session.sshPrompt != nil }
        let prompt = try XCTUnwrap(session.sshPrompt)
        guard case .host(_, let assessment) = prompt.kind else { return XCTFail("Changed host must request identity confirmation") }
        XCTAssertEqual(assessment, .changed(previous: oldKey))
        XCTAssertEqual(replacement.state.authCount, 0)
        XCTAssertEqual(replacement.state.forwardCount, 0)
        session.cancelSSHPrompt(promptID: prompt.id)
        try await Task.sleep(nanoseconds: 2_200_000_000)
        XCTAssertNil(session.sshPrompt)
        XCTAssertFalse(session.isAwaitingAutomaticReconnect)
        XCTAssertEqual(try trust.assess(replacement.identity, at: settings.server), .changed(previous: oldKey))
        XCTAssertEqual(replacement.state.authCount, 0)
        XCTAssertEqual(replacement.state.forwardCount, 0)
    }

    @MainActor
    func testSessionAutomaticallyRebuildsAuthenticatedSSHTunnelAfterSocketLoss() async throws {
        let ready = expectation(description: "SSH reconnect desktop ready")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        addTeardownBlock { server.stop() }
        await fulfillment(of: [ready], timeout: 3)
        let port = try XCTUnwrap(server.listener.port).rawValue
        let (fixture, _, trust) = try await environment(targetPort: port)
        let access = SessionSSHAccess()
        access.readStatus = errSecInteractionNotAllowed
        let session = SessionViewModel(device: RemoteDevice(name: "SSH recovery QA", host: "direct-route.invalid",
            port: port, ssh: try fixture.settings()), password: nil, isTemporary: true,
            sshCredentials: SSHCredentialStore(service: "ssh-recovery-qa", access: access),
            sshTrust: trust, initialSSHPassword: fixture.password)
        defer { session.requestDisconnect() }
        session.startSession()
        try await waitForSession { session.sshPrompt != nil }
        session.approveSSHHost(promptID: try XCTUnwrap(session.sshPrompt).id)
        try await waitForSession { session.sessionState == .connected }
        server.sendGreenFrame()
        try await waitForSession { session.hasReceivedFirstFrame }
        session.zoomScale = 2.5
        session.viewOffset = CGSize(width: 15, height: 20)
        try await fixture.dropActiveConnections()
        try await waitForSession { fixture.state.authCount >= 2 && session.sessionState == .connected }
        XCTAssertNil(session.sshPrompt, "Previously trusted identity must not prompt again")
        server.sendGreenFrame()
        try await waitForSession { session.hasReceivedFirstFrame }
        XCTAssertEqual(fixture.state.forwardCount, 2)
        XCTAssertEqual(session.zoomScale, 2.5)
        XCTAssertEqual(session.viewOffset, CGSize(width: 15, height: 20))
        XCTAssertNil(access.value)
    }

    func testActualRefusedSSHSocketIsRetryableWithoutPublishingForward() async throws {
        let (fixture, tunnel, trust) = try await environment()
        let settings = try fixture.settings()
        let remotePort = fixture.echoPort
        try await fixture.stop()
        do {
            _ = try await tunnel.start(settings: settings, password: fixture.password, remotePort: remotePort, trust: trust) { _, _ in
                XCTFail("Refused socket cannot request host trust"); return false
            }
            XCTFail("Stopped SSH listener must refuse the connection")
        } catch {
            XCTAssertTrue(SessionReconnectPolicy.retriesSSHError(error), "Actual socket refusal must enter the bounded retry policy")
        }
        let port = await tunnel.localPort
        XCTAssertNil(port)
    }

    func testPrivateKeyAuthenticatesAndForwardsRealBytes() async throws {
        let data = Data(P256.Signing.PrivateKey().pemRepresentation.utf8)
        let key = try SSHPrivateKey.decode(data)
        let (fixture, tunnel, trust) = try await environment(authorizedKey: key.publicKey)
        let settings = try XCTUnwrap(SSHConnectionSettings(server: fixture.settings().server,
            username: "QA", authentication: .privateKey(UUID())))
        let port = try await tunnel.start(settings: settings, privateKeyData: data, remotePort: fixture.echoPort,
            trust: trust, decideHost: { _, _ in true })
        try await assertEcho(port: port, data: Data(repeating: 0xAC, count: 4096))
        XCTAssertEqual(fixture.state.forwardCount, 1)
    }

    func testDecryptedPKCS8AuthenticatesAndForwardsRealBytes() async throws {
        #if os(macOS)
        let openssl = URL(fileURLWithPath: "/opt/homebrew/opt/openssl@3/bin/openssl")
        guard FileManager.default.isExecutableFile(atPath: openssl.path) else { throw XCTSkip("OpenSSL 3 oracle unavailable") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aetherscreens-encrypted-auth-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.pem")
        let encrypted = directory.appendingPathComponent("encrypted.pem")
        let phraseFile = directory.appendingPathComponent("phrase")
        let original = Data(P384.Signing.PrivateKey().pemRepresentation.utf8)
        try original.write(to: source)
        try Data("QA encrypted auth phrase".utf8).write(to: phraseFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: phraseFile.path)
        let process = Process()
        process.executableURL = openssl
        process.arguments = ["pkcs8", "-topk8", "-in", source.path, "-out", encrypted.path,
            "-v2", "aes-256-cbc", "-iter", "1000", "-passout", "file:" + phraseFile.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw SSHPrivateKey.Failure.invalid }
        let data = try EncryptedPKCS8PrivateKey.decrypt(Data(contentsOf: encrypted), passphrase: "QA encrypted auth phrase")
        let key = try SSHPrivateKey.decode(original)
        let (fixture, tunnel, trust) = try await environment(authorizedKey: key.publicKey)
        let settings = try XCTUnwrap(SSHConnectionSettings(server: fixture.settings().server,
            username: "QA", authentication: .privateKey(UUID())))
        let port = try await tunnel.start(settings: settings, privateKeyData: data, remotePort: fixture.echoPort,
            trust: trust, decideHost: { _, _ in true })
        try await assertEcho(port: port, data: Data(repeating: 0xBC, count: 4096))
        XCTAssertEqual(fixture.state.forwardCount, 1)
        #else
        throw XCTSkip("External OpenSSL oracle requires macOS")
        #endif
    }

    func testWrongPrivateKeyDoesNotPublishListener() async throws {
        let authorized = NIOSSHPrivateKey(p256Key: P256.Signing.PrivateKey())
        let (fixture, tunnel, trust) = try await environment(authorizedKey: authorized.publicKey)
        let settings = try XCTUnwrap(SSHConnectionSettings(server: fixture.settings().server,
            username: "QA", authentication: .privateKey(UUID())))
        do {
            _ = try await tunnel.start(settings: settings,
                privateKeyData: Data(P256.Signing.PrivateKey().pemRepresentation.utf8), remotePort: fixture.echoPort,
                trust: trust, decideHost: { _, _ in true })
            XCTFail("A different private key must fail authentication")
        } catch { XCTAssertEqual(error as? SSHForwardingTunnel.Failure, .authenticationFailed) }
        let port = await tunnel.localPort
        XCTAssertNil(port)
        XCTAssertEqual(fixture.state.forwardCount, 0)
    }

    @MainActor
    func testTemporaryPrivateKeyReceivesFramebufferWithoutVaultAccess() async throws {
        let ready = expectation(description: "Key-auth desktop listening")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        addTeardownBlock { server.stop() }
        await fulfillment(of: [ready], timeout: 3)
        let port = try XCTUnwrap(server.listener.port).rawValue
        let data = Data(P256.Signing.PrivateKey().pemRepresentation.utf8)
        let key = try SSHPrivateKey.decode(data)
        let (fixture, _, trust) = try await environment(targetPort: port, authorizedKey: key.publicKey)
        let access = SessionSSHAccess(); access.readStatus = errSecInteractionNotAllowed; access.writeStatus = errSecInteractionNotAllowed
        let vault = SSHCredentialStore(service: "temporary-private-key-qa", access: access)
        let settings = try XCTUnwrap(SSHConnectionSettings(server: fixture.settings().server,
            username: "QA", authentication: .privateKey(UUID())))
        let device = RemoteDevice(name: "Key QA", host: "direct-route.invalid", port: port, ssh: settings)
        let session = SessionViewModel(device: device, password: nil, isTemporary: true, sshCredentials: vault,
            sshTrust: trust, initialSSHPrivateKey: data)
        defer { session.endSession(); session.client.disconnect() }
        session.startSession()
        try await waitForSession { session.sshPrompt != nil }
        let prompt = try XCTUnwrap(session.sshPrompt)
        guard case .host = prompt.kind else { return XCTFail("Key authentication must not prompt for a password") }
        session.approveSSHHost(promptID: prompt.id)
        try await waitForSession { session.sessionState == .connected }
        server.sendGreenFrame()
        try await waitForSession { session.hasReceivedFirstFrame }
        XCTAssertNil(access.value)
        XCTAssertGreaterThan(fixture.state.authCount, 0)
        XCTAssertEqual(fixture.state.forwardCount, 1)
    }

    @MainActor
    func testTemporaryQuickSSHUsesMemoryPasswordAndReceivesActualFramebuffer() async throws {
        let ready = expectation(description: "Temporary desktop listening")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        addTeardownBlock { server.stop() }
        await fulfillment(of: [ready], timeout: 3)
        let port = try XCTUnwrap(server.listener.port).rawValue
        let (fixture, _, trust) = try await environment(targetPort: port)
        let access = SessionSSHAccess()
        access.readStatus = errSecInteractionNotAllowed
        access.writeStatus = errSecInteractionNotAllowed
        let vault = SSHCredentialStore(service: "temporary-quick-qa", access: access)
        let suite = "test.quick.ssh." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DeviceStore(userDefaults: defaults, sshCredentials: vault)
        let discovery = BonjourDiscoveryService()
        defer { discovery.stopDiscovery() }
        let library = DeviceListViewModel(store: store, bonjourService: discovery, sshTrust: trust)
        let request = try XCTUnwrap(ConnectionRequest(host: "direct-route.invalid", port: String(port),
            ssh: fixture.settings(), sshPassword: fixture.password))
        let session = try library.prepareQuickSession(request, saveComputer: false)
        defer { session.endSession(); session.client.disconnect() }
        session.startSession()
        try await waitForSession { session.sshPrompt != nil }
        let prompt = try XCTUnwrap(session.sshPrompt)
        guard case .host = prompt.kind else { return XCTFail("In-memory password should skip password prompt and vault read") }
        session.approveSSHHost(promptID: prompt.id)
        try await waitForSession { session.sessionState == .connected }
        server.sendGreenFrame()
        try await waitForSession { session.hasReceivedFirstFrame }
        XCTAssertTrue(store.devices.isEmpty)
        XCTAssertNil(defaults.data(forKey: DeviceStore.storageKey))
        XCTAssertNil(access.value)
    }
    @MainActor
    func testDeniedSSHPasswordReadFailsClosedAndDeniedSaveKeepsPrompt() async throws {
        let address = try XCTUnwrap(SSHServerAddress(host: "127.0.0.1", port: 9))
        let settings = try XCTUnwrap(SSHConnectionSettings(server: address, username: "qa"))
        let device = RemoteDevice(name: "Vault QA", host: "localhost", ssh: settings)
        let access = SessionSSHAccess()
        access.readStatus = errSecInteractionNotAllowed
        let model = SessionViewModel(device: device, password: nil,
            sshCredentials: SSHCredentialStore(service: "vault-session-qa", access: access))
        defer { model.endSession(); model.client.disconnect() }
        model.startSession()
        try await waitForSession { if case .failed = model.sessionState { return true }; return false }
        XCTAssertEqual(model.client.state, .disconnected)
        XCTAssertNil(model.sshPrompt, "A denied vault read must not become an empty password prompt")
        access.readStatus = nil
        access.writeStatus = errSecInteractionNotAllowed
        model.startSession()
        try await waitForSession { model.sshPrompt != nil }
        let prompt = try XCTUnwrap(model.sshPrompt)
        model.submitSSHPassword("QA dummy", remember: true, promptID: prompt.id)
        XCTAssertEqual(model.sshPrompt?.id, prompt.id)
        XCTAssertNotNil(model.sshPrompt?.error)
        XCTAssertNil(access.value)
        XCTAssertEqual(model.client.state, .disconnected)
        model.endSession()
        XCTAssertNil(model.sshPrompt)
    }
    @MainActor
    private func waitForSession(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        guard condition() else { XCTFail("Session condition timed out"); throw SSHForwardingTunnel.Failure.timedOut }
    }

    @MainActor
    func testSessionInteractivePasswordHostTrustCancellationAndRestart() async throws {
        let ready = expectation(description: "Session RFB listening")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        addTeardownBlock { server.stop() }
        await fulfillment(of: [ready], timeout: 3)
        let port = try XCTUnwrap(server.listener.port).rawValue
        let (fixture, _, trust) = try await environment(targetPort: port)
        let credentials = SSHCredentialStore(service: "session-qa", access: SessionSSHAccess())
        let device = RemoteDevice(name: "SSH QA", host: "direct-route.invalid", port: port, ssh: try fixture.settings())
        let model = SessionViewModel(device: device, password: nil, isTemporary: true,
            sshCredentials: credentials, sshTrust: trust)
        defer { model.endSession(); model.client.disconnect() }
        model.startSession()
        try await waitForSession { model.sshPrompt != nil }
        let passwordPrompt = try XCTUnwrap(model.sshPrompt)
        model.submitSSHPassword(fixture.password, remember: false, promptID: passwordPrompt.id)
        try await waitForSession { model.sshPrompt != nil }
        let rejectedHostPrompt = try XCTUnwrap(model.sshPrompt)
        guard case .host = rejectedHostPrompt.kind else { return XCTFail("Expected host identity prompt") }
        model.cancelSSHPrompt(promptID: rejectedHostPrompt.id)
        model.approveSSHHost(promptID: rejectedHostPrompt.id)
        XCTAssertEqual(model.sessionState, .disconnected)
        XCTAssertEqual(fixture.state.authCount, 0)
        model.startSession()
        try await waitForSession { model.sshPrompt != nil }
        let replacementPassword = try XCTUnwrap(model.sshPrompt)
        model.submitSSHPassword(fixture.password, remember: true, promptID: replacementPassword.id)
        XCTAssertNil(try credentials.load(kind: .password, reference: device.id), "Temporary sessions never save passwords")
        try await waitForSession { model.sshPrompt != nil }
        let replacementHost = try XCTUnwrap(model.sshPrompt)
        model.cancelSSHPrompt(promptID: rejectedHostPrompt.id)
        XCTAssertEqual(model.sshPrompt?.id, replacementHost.id, "An old sheet dismissal cannot cancel its replacement")
        model.approveSSHHost(promptID: replacementHost.id)
        try await waitForSession { model.sessionState == .connected }
        server.sendGreenFrame()
        try await waitForSession { model.hasReceivedFirstFrame }
        XCTAssertEqual(fixture.state.authCount, 1)
    }

    @MainActor
    func testSessionExplicitDisconnectDrainsFinalChordAndReconnects() async throws {
        let ready = expectation(description: "Drain RFB listening")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        addTeardownBlock { server.stop() }
        await fulfillment(of: [ready], timeout: 3)
        let port = try XCTUnwrap(server.listener.port).rawValue
        let (fixture, _, trust) = try await environment(targetPort: port)
        let access = SessionSSHAccess(); access.value = Data(fixture.password.utf8)
        let credentials = SSHCredentialStore(service: "session-drain-qa", access: access)
        let device = RemoteDevice(name: "Drain QA", host: "direct-route.invalid", port: port, ssh: try fixture.settings())
        let suite = "test.ssh.session." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); DisconnectActionStore.shared.remove(for: device.id) }
        let model = SessionViewModel(device: device, password: nil,
            deviceStore: DeviceStore(userDefaults: defaults), sshCredentials: credentials, sshTrust: trust)
        defer { model.endSession(); model.client.disconnect() }
        DisconnectActionStore.shared.save(.lockScreen, for: device.id)
        model.startSession()
        try await waitForSession { model.sshPrompt != nil }
        model.approveSSHHost(promptID: try XCTUnwrap(model.sshPrompt).id)
        try await waitForSession { model.sessionState == .connected }
        let chord = expectation(description: "VM final complete chord received")
        server.onKey = { if $0.key == MacKeyMap.controlLeft && !$0.down { chord.fulfill() } }
        model.requestDisconnect()
        model.endSession()
        model.requestDisconnect()
        await fulfillment(of: [chord], timeout: 3)
        let expected = MacKeyMap.MacShortcut.lockScreen.keySequence
        XCTAssertEqual(server.keys.map(\.key), expected.map(\.key))
        XCTAssertEqual(server.keys.map(\.down), expected.map(\.down))
        server.onKey = nil
        try await waitForSession { model.client.state == .disconnected }
        model.startSession()
        try await waitForSession { model.sessionState == .connected }
        XCTAssertNil(model.sshPrompt, "Trusted host and stored password skip prompts")
        XCTAssertEqual(fixture.state.authCount, 2)
    }

    @MainActor
    func testSyncedSSHAccountPromptsOnceAndRememberedPasswordReconnects() async throws {
        let ready = expectation(description: "Synced credential RFB listening")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        addTeardownBlock { server.stop() }
        await fulfillment(of: [ready], timeout: 3)
        let port = try XCTUnwrap(server.listener.port).rawValue
        let (fixture, _, trust) = try await environment(targetPort: port)
        let settings = try fixture.settings()
        let access = SessionSSHAccess()
        access.value = Data(fixture.password.utf8)
        let credentials = SSHCredentialStore(service: "sync-session-qa", access: access)
        let suite = "test.ssh.sync-session." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DeviceStore(userDefaults: defaults, sshCredentials: credentials)
        var device = RemoteDevice(name: "Synced SSH", host: "direct-route.invalid", port: port)
        device.ssh = try XCTUnwrap(SSHConnectionSettings(server: settings.server, username: "old-account"))
        store.addDevice(device)
        device.ssh = settings
        var journal = ComputerSyncJournal()
        try journal.upsert(.init(device: device))
        try store.applySyncJournal(journal)
        let model = SessionViewModel(device: device, password: nil, deviceStore: store,
            sshCredentials: credentials, sshTrust: trust)
        defer { model.endSession(); model.client.disconnect() }
        model.startSession()
        try await waitForSession { model.sshPrompt != nil }
        let passwordPrompt = try XCTUnwrap(model.sshPrompt)
        guard case .password = passwordPrompt.kind else { return XCTFail("Changed account requires password prompt") }
        model.submitSSHPassword(fixture.password, remember: true, promptID: passwordPrompt.id)
        XCTAssertEqual(try store.getSSHPassword(for: device), Data(fixture.password.utf8))
        try await waitForSession { model.sshPrompt != nil }
        model.approveSSHHost(promptID: try XCTUnwrap(model.sshPrompt).id)
        try await waitForSession { model.sessionState == .connected }
        model.endSession()
        try await waitForSession { model.client.state == .disconnected }
        model.startSession()
        try await waitForSession { model.sessionState == .connected }
        XCTAssertNil(model.sshPrompt)
        XCTAssertEqual(fixture.state.authCount, 2)
    }

    func testDeviceSSHConfigurationRoundTripsAndLegacyDevicesRemainDirect() throws {
        let device = RemoteDevice(name: "Legacy QA", host: "localhost")
        let legacy = try JSONEncoder().encode(device)
        XCTAssertNil(try JSONDecoder().decode(RemoteDevice.self, from: legacy).ssh)
        var secure = device
        secure.ssh = SSHConnectionSettings(server: try XCTUnwrap(SSHServerAddress(host: "ssh.example")), username: "qa")
        XCTAssertEqual(try JSONDecoder().decode(RemoteDevice.self, from: JSONEncoder().encode(secure)), secure)
    }
    func testRequiredForwardingNeverFallsBackToDirectConnection() async throws {
        let ready = expectation(description: "Direct target listening")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        addTeardownBlock { server.stop() }
        await fulfillment(of: [ready], timeout: 3)
        let port = try XCTUnwrap(server.listener.port).rawValue
        let client = RFBClient(host: "127.0.0.1", port: port, requiresLoopbackForwarding: true)
        addTeardownBlock { client.disconnect() }
        client.connect()
        XCTAssertEqual(client.state, .failed("SSH forwarding is not ready"))
        // Clearing a previously configured tunnel cannot weaken the policy.
        XCTAssertTrue(client.configureLoopbackForwarding(port: port))
        XCTAssertTrue(client.configureLoopbackForwarding(port: nil))
        client.connect()
        XCTAssertEqual(client.state, .failed("SSH forwarding is not ready"))
    }
    private func environment(stalled: Bool = false, port: Int = 0, targetPort: UInt16? = nil, authorizedKey: NIOSSHPublicKey? = nil,
                             hostKey: NIOSSHPrivateKey? = nil, password: String? = nil) async throws -> (SSHFixture, SSHForwardingTunnel, SSHHostTrustStore) {
        let fixture = try await SSHFixture(stalled: stalled, port: port, targetPort: targetPort, authorizedKey: authorizedKey,
                                           hostKey: hostKey, password: password)
        let tunnel = SSHForwardingTunnel(handshakeTimeout: .milliseconds(500))
        let suite = "test.aetherscreens.ssh-forward." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let trust = SSHHostTrustStore(defaults: defaults)
        addTeardownBlock {
            await tunnel.stop()
            try await fixture.stop()
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        return (fixture, tunnel, trust)
    }

    func testRFBFramebufferAndCompleteDisconnectChordTravelThroughSSH() async throws {
        let ready = expectation(description: "RFB target ready")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        addTeardownBlock { server.stop() }
        await fulfillment(of: [ready], timeout: 3)
        let targetPort = try XCTUnwrap(server.listener.port).rawValue
        let (fixture, tunnel, trust) = try await environment(targetPort: targetPort)
        let forwarded = try await tunnel.start(settings: fixture.settings(), password: fixture.password, remotePort: targetPort, trust: trust) { _, _ in true }
        // An unresolvable logical host makes accidental direct fallback observable.
        let client = RFBClient(host: "rfb-target.invalid", port: targetPort, requiresLoopbackForwarding: true)
        addTeardownBlock { client.disconnect() }
        XCTAssertFalse(client.configureLoopbackForwarding(port: 0))
        XCTAssertTrue(client.configureLoopbackForwarding(port: forwarded))
        let connected = expectation(description: "RFB initialized through SSH")
        let frame = expectation(description: "Real green framebuffer through SSH")
        let lockChord = expectation(description: "Complete final lock chord through SSH")
        let unwantedRTT = expectation(description: "Local proxy RTT must not represent remote latency")
        unwantedRTT.isInverted = true
        client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        client.onFrameUpdated = { frame.fulfill() }
        client.onTransportRTT = { _ in unwantedRTT.fulfill() }
        server.onKey = { if $0.key == MacKeyMap.controlLeft && !$0.down { lockChord.fulfill() } }
        client.connect()
        await fulfillment(of: [connected], timeout: 3)
        XCTAssertFalse(client.configureLoopbackForwarding(port: nil), "Active transport cannot be retargeted")
        // Receive after the normal TCP-report deadline so reporting would occur
        // on a direct socket. No loopback latency is published for forwarding.
        try await Task.sleep(nanoseconds: 1_100_000_000)
        server.sendGreenFrame()
        await fulfillment(of: [frame, unwantedRTT], timeout: 1)
        client.framebuffer.withPixelBytes { bytes, width, height in
            XCTAssertEqual(width, 16); XCTAssertEqual(height, 16)
            XCTAssertEqual(bytes[0], 0); XCTAssertEqual(bytes[1], 255); XCTAssertEqual(bytes[2], 0)
        }
        let chord = MacKeyMap.MacShortcut.lockScreen.keySequence
        client.disconnect(afterSendingKeySequence: chord)
        await fulfillment(of: [lockChord], timeout: 3)
        XCTAssertEqual(server.keys.map(\.key), chord.map(\.key))
        XCTAssertEqual(server.keys.map(\.down), chord.map(\.down))
        XCTAssertEqual(fixture.state.authCount, 1)
        XCTAssertEqual(fixture.state.forwardCount, 1)
        XCTAssertEqual(client.host, "rfb-target.invalid")
        XCTAssertTrue(client.configureLoopbackForwarding(port: nil))
    }

    func testAuthenticatedSSHForwardsLargeBidirectionalPayloadAndReusesTrustedIdentity() async throws {
        let (fixture, tunnel, trust) = try await environment()
        let decisions = Counter()
        let settings = try fixture.settings()
        let port = try await tunnel.start(settings: settings, password: fixture.password, remotePort: fixture.echoPort, trust: trust) { _, assessment in
            XCTAssertEqual(assessment, .unknown); decisions.increment(); return true
        }
        XCTAssertEqual(try trust.assess(fixture.identity, at: settings.server), .trusted)
        let payload = Data((0..<(2 * 1024 * 1024)).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        try await assertEcho(port: port, data: payload)
        XCTAssertEqual(fixture.state.authCount, 1)
        XCTAssertEqual(fixture.state.forwardCount, 1)
        await tunnel.stop()
        let stopped = await tunnel.localPort
        XCTAssertNil(stopped)
        let restarted = try await tunnel.start(settings: settings, password: fixture.password, remotePort: fixture.echoPort, trust: trust) { _, _ in
            XCTFail("Trusted host must not prompt again"); return false
        }
        try await assertEcho(port: restarted, data: Data([0, 1, 2, 255]))
        XCTAssertEqual(decisions.value, 1)
        XCTAssertEqual(fixture.state.authCount, 2)
    }

    func testRejectedIdentityNeverSendsCredentialsOrStartsForwarding() async throws {
        let (fixture, tunnel, trust) = try await environment()
        let settings = try fixture.settings()
        do {
            _ = try await tunnel.start(settings: settings, password: fixture.password, remotePort: fixture.echoPort, trust: trust) { _, _ in false }
            XCTFail("Rejected identity must fail")
        } catch { XCTAssertEqual(error as? SSHForwardingTunnel.Failure, .hostKeyRejected) }
        XCTAssertEqual(fixture.state.authCount, 0)
        XCTAssertEqual(fixture.state.forwardCount, 0)
        XCTAssertEqual(try trust.assess(fixture.identity, at: settings.server), .unknown)
        let port = await tunnel.localPort
        XCTAssertNil(port)
    }

    func testWrongPasswordDoesNotPublishListener() async throws {
        let (fixture, tunnel, trust) = try await environment()
        do {
            _ = try await tunnel.start(settings: fixture.settings(), password: UUID().uuidString, remotePort: fixture.echoPort, trust: trust) { _, _ in true }
            XCTFail("Wrong authentication must fail")
        } catch { XCTAssertEqual(error as? SSHForwardingTunnel.Failure, .authenticationFailed) }
        XCTAssertEqual(fixture.state.authCount, 1)
        XCTAssertEqual(fixture.state.forwardCount, 0)
        let port = await tunnel.localPort
        XCTAssertNil(port)
    }

    func testNetworkStallTimesOutButIdentityDecisionDoesNot() async throws {
        let (stalled, tunnel, trust) = try await environment(stalled: true)
        let started = Date()
        do {
            _ = try await tunnel.start(settings: stalled.settings(), password: stalled.password, remotePort: stalled.echoPort, trust: trust) { _, _ in
                XCTFail("Silent server cannot provide identity"); return false
            }
            XCTFail("Silent server must time out")
        } catch { XCTAssertEqual(error as? SSHForwardingTunnel.Failure, .timedOut) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        let (fixture, interactive, secondTrust) = try await environment()
        let port = try await interactive.start(settings: fixture.settings(), password: fixture.password, remotePort: fixture.echoPort, trust: secondTrust) { _, _ in
            try? await Task.sleep(nanoseconds: 800_000_000) // Longer than the network timeout.
            return true
        }
        try await assertEcho(port: port, data: Data([17, 18]))
    }

    func testLateApprovalAfterCancellationCannotTrustOldHostOrCloseReplacement() async throws {
        let (first, tunnel, trust) = try await environment()
        let (second, _, _) = try await environment()
        let entered = expectation(description: "Identity prompt entered")
        let gate = DecisionGate()
        let firstSettings = try first.settings()
        let pending = Task {
            try await tunnel.start(settings: firstSettings, password: first.password, remotePort: first.echoPort, trust: trust) { _, _ in
                entered.fulfill(); return await gate.wait()
            }
        }
        await fulfillment(of: [entered], timeout: 3)
        await tunnel.stop()
        let replacement = try await tunnel.start(settings: second.settings(), password: second.password, remotePort: second.echoPort, trust: trust) { _, _ in true }
        await gate.resolve(true)
        do { _ = try await pending.value; XCTFail("Cancelled start must fail") }
        catch { XCTAssertEqual(error as? SSHForwardingTunnel.Failure, .cancelled) }
        XCTAssertEqual(try trust.assess(first.identity, at: firstSettings.server), .unknown)
        let current = await tunnel.localPort
        XCTAssertEqual(current, replacement)
        try await assertEcho(port: replacement, data: Data([31, 32]))
        XCTAssertEqual(first.state.authCount, 0)
    }

    func testChangedKeyRequiresNewExplicitDecisionOnSameServerAddress() async throws {
        let (first, tunnel, trust) = try await environment()
        let settings = try first.settings()
        _ = try await tunnel.start(settings: settings, password: first.password, remotePort: first.echoPort, trust: trust) { _, _ in true }
        await tunnel.stop()
        let sshPort = Int(first.sshPort), oldKey = try first.identity
        try await first.stop()
        let (replacement, _, _) = try await environment(port: sshPort)
        do {
            _ = try await tunnel.start(settings: replacement.settings(), password: replacement.password, remotePort: replacement.echoPort, trust: trust) { key, assessment in
                XCTAssertNotEqual(key, oldKey)
                XCTAssertEqual(assessment, .changed(previous: oldKey)); return false
            }
            XCTFail("Changed key must not be silently accepted")
        } catch { XCTAssertEqual(error as? SSHForwardingTunnel.Failure, .hostKeyRejected) }
        XCTAssertEqual(replacement.state.authCount, 0)
        XCTAssertEqual(try trust.assess(replacement.identity, at: settings.server), .changed(previous: oldKey))
        let port = try await tunnel.start(settings: replacement.settings(), password: replacement.password, remotePort: replacement.echoPort, trust: trust) { _, assessment in
            XCTAssertEqual(assessment, .changed(previous: oldKey)); return true
        }
        XCTAssertEqual(try trust.assess(replacement.identity, at: settings.server), .trusted)
        try await assertEcho(port: port, data: Data([81, 82]))
    }

    private func assertEcho(port: UInt16, data: Data) async throws {
        let received = try await echo(port: port, data: data)
        XCTAssertEqual(received, data)
    }

    private func echo(port: UInt16, data: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            EchoProbe(port: port, data: data, continuation: continuation).start()
        }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

private actor DecisionGate {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var result: Bool?
    func wait() async -> Bool {
        if let result { return result }
        return await withCheckedContinuation { continuation = $0 }
    }
    func resolve(_ result: Bool) { self.result = result; continuation?.resume(returning: result); continuation = nil }
}

private final class SSHFixture: @unchecked Sendable {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let password: String
    let state = State()
    let key: NIOSSHPrivateKey
    private var ssh: Channel!
    private var echoServer: Channel!
    var sshPort: UInt16 { UInt16(ssh.localAddress!.port!) }
    var echoPort: UInt16 { UInt16(echoServer.localAddress!.port!) }
    var identity: SSHHostKey {
        get throws {
            let encoded = String(openSSHPublicKey: key.publicKey).split(separator: " ")
            return try SSHHostKey(validatedKeyBlob: XCTUnwrap(Data(base64Encoded: String(encoded[1]))))
        }
    }
    func settings() throws -> SSHConnectionSettings {
        try XCTUnwrap(SSHConnectionSettings(server: XCTUnwrap(SSHServerAddress(host: "127.0.0.1", port: sshPort)), username: "QA"))
    }
    init(stalled: Bool, port: Int, targetPort: UInt16?, authorizedKey: NIOSSHPublicKey?,
         hostKey: NIOSSHPrivateKey? = nil, password: String? = nil) async throws {
        self.key = hostKey ?? NIOSSHPrivateKey(ed25519Key: .init())
        self.password = password ?? UUID().uuidString
        let loop = group.next(), state = state, key = key, password = self.password
        do {
            echoServer = try await ServerBootstrap(group: loop)
                .serverChannelInitializer { channel in state.register(channel); return loop.makeSucceededFuture(()) }
                .childChannelInitializer { channel in
                    state.register(channel)
                    return channel.pipeline.addHandler(EchoHandler())
                }.bind(host: "127.0.0.1", port: 0).get()
            let target = targetPort ?? echoPort
            ssh = try await ServerBootstrap(group: loop)
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .serverChannelInitializer { channel in state.register(channel); return loop.makeSucceededFuture(()) }
                .childChannelInitializer { channel in
                    state.register(channel)
                    if stalled { return channel.pipeline.addHandler(SilentHandler()) }
                    return loop.makeCompletedFuture {
                        try channel.pipeline.syncOperations.addHandlers([
                            NIOSSHHandler(role: .server(.init(hostKeys: [key], userAuthDelegate: PasswordServer(password: password, state: state, authorizedKey: authorizedKey))),
                                allocator: channel.allocator, inboundChildChannelInitializer: { child, type in
                                    guard case .directTCPIP(let request) = type, request.targetHost == "127.0.0.1", request.targetPort == Int(target) else {
                                        return loop.makeFailedFuture(SSHForwardingTunnel.Failure.invalidForward)
                                    }
                                    state.forward.increment(); state.register(child)
                                    return child.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).flatMap {
                                        loop.makeCompletedFuture {
                                            let (ours, theirs) = SSHForwardingGlue.matchedPair()
                                            try child.pipeline.syncOperations.addHandlers([SSHForwardingCodec(), ours])
                                            return NIOLoopBound(theirs, eventLoop: loop)
                                        }
                                    }.flatMap { glue in
                                        ClientBootstrap(group: loop)
                                            .channelOption(ChannelOptions.allowRemoteHalfClosure, value: true)
                                            .channelInitializer { tcp in
                                                state.register(tcp)
                                                return loop.makeCompletedFuture { try tcp.pipeline.syncOperations.addHandler(glue.value) }
                                            }.connect(host: "127.0.0.1", port: Int(target)).map { _ in }
                                    }
                                }), FixtureErrors()
                        ])
                    }
                }.bind(host: "127.0.0.1", port: port).get()
        } catch { try? await group.shutdownGracefully(); throw error }
    }
    func stop() async throws {
        guard let channels = state.stop() else { return }
        for channel in channels { try? await channel.close().get() }
        try await group.shutdownGracefully()
    }
    func dropActiveConnections() async throws {
        let listeners = Set([ObjectIdentifier(ssh), ObjectIdentifier(echoServer)])
        for channel in state.snapshot() where !listeners.contains(ObjectIdentifier(channel)) {
            try? await channel.close().get()
        }
    }
    final class State: @unchecked Sendable {
        let auth = Counter(), forward = Counter()
        private let lock = NSLock()
        private var channels: [Channel] = []
        private var stopped = false
        var authCount: Int { auth.value }
        var forwardCount: Int { forward.value }
        func register(_ channel: Channel) {
            lock.lock()
            if stopped { lock.unlock(); channel.close(promise: nil) }
            else { channels.append(channel); lock.unlock() }
        }
        func stop() -> [Channel]? {
            lock.lock(); defer { lock.unlock() }
            guard !stopped else { return nil }
            stopped = true
            let saved = channels; channels.removeAll(); return saved
        }
        func snapshot() -> [Channel] { lock.lock(); defer { lock.unlock() }; return channels }
    }
}

private final class PasswordServer: NIOSSHServerUserAuthenticationDelegate {
    let password: String, state: SSHFixture.State
    let authorizedKey: NIOSSHPublicKey?
    init(password: String, state: SSHFixture.State, authorizedKey: NIOSSHPublicKey?) { self.password = password; self.state = state; self.authorizedKey = authorizedKey }
    var supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods { authorizedKey == nil ? .password : .publicKey }
    func requestReceived(request: NIOSSHUserAuthenticationRequest, responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
        state.auth.increment()
        guard request.username == "QA" else { responsePromise.succeed(.failure); return }
        if let authorizedKey {
            guard case .publicKey(let value) = request.request, value.publicKey == authorizedKey else { responsePromise.succeed(.failure); return }
        } else {
            guard case .password(let value) = request.request, value.password == password else { responsePromise.succeed(.failure); return }
        }
        responsePromise.succeed(.success)
    }
}
private final class EchoHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    func channelRead(context: ChannelHandlerContext, data: NIOAny) { context.writeAndFlush(data, promise: nil) }
}
private final class SilentHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {}
}
private final class FixtureErrors: ChannelInboundHandler {
    typealias InboundIn = Any
    func errorCaught(context: ChannelHandlerContext, error: Error) { context.close(promise: nil) }
}

private final class EchoProbe: @unchecked Sendable {
    let queue = DispatchQueue(label: "aetherscreens.ssh-echo-probe")
    let connection: NWConnection
    let payload: Data
    var received = Data()
    var finished = false
    let continuation: CheckedContinuation<Data, Error>
    init(port: UInt16, data: Data, continuation: CheckedContinuation<Data, Error>) {
        connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        payload = data; self.continuation = continuation
    }
    func start() {
        connection.stateUpdateHandler = { [self] state in
            switch state {
            case .ready:
                connection.send(content: payload, completion: .contentProcessed { [self] error in
                    if let error { finish(.failure(error)) }
                }); read()
            case .failed(let error): finish(.failure(error))
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 8) { [self] in finish(.failure(SSHForwardingTunnel.Failure.timedOut)) }
    }
    func read() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, end, error in
            if let error { finish(.failure(error)); return }
            if let data { received.append(data) }
            if received.count >= payload.count { finish(.success(received)) }
            else if end { finish(.failure(SSHForwardingTunnel.Failure.closed)) }
            else if !finished { read() }
        }
    }
    func finish(_ result: Result<Data, Error>) {
        guard !finished else { return }; finished = true
        connection.stateUpdateHandler = nil
        connection.cancel(); continuation.resume(with: result)
    }
}
