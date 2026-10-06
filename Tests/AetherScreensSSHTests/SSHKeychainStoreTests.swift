import XCTest
import Foundation
import Security
import Crypto
import NIOSSH
@testable import AetherScreensSSH
@testable import AetherScreensCore

final class SSHKeychainStoreTests: XCTestCase {
    @MainActor
    func testForgetReviewedIdentityPreservesCredentialsAndOtherEndpoints() async throws {
        let suite = "test.aetherscreens.ssh.forget." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = FixtureSecretBackend()
        let keys = SSHKeychainStore(backend: backend)
        let store = TestStorage.make(userDefaults: defaults, sshKeychain: keys)
        let discovery = BonjourDiscoveryService()
        defer { discovery.stopDiscovery() }
        let vm = DeviceListViewModel(store: store, bonjourService: discovery)
        let configuration = try SSHConfiguration(host: "ssh.invalid", username: "qa")
        let otherPort = try SSHConfiguration(host: "ssh.invalid", port: 2222, username: "qa")
        let identity = SSHHostKeyIdentity(key: NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey()).publicKey)
        let request = try XCTUnwrap(ConnectionRequest(host: "rfb.invalid", sshConfiguration: configuration,
                                                      sshCredentials: .password("synthetic-only")))
        try vm.saveConnection(request)
        try keys.approve(identity, for: configuration)
        try keys.approve(identity, for: otherPort)
        XCTAssertEqual(try vm.trustedSSHIdentity(for: request.device), identity)
        backend.requireBackgroundAccess = true
        let loadedIdentity = try await vm.loadTrustedSSHIdentity(for: request.device)
        XCTAssertEqual(loadedIdentity, identity)
        backend.failure = .keychain(errSecInteractionNotAllowed)
        do {
            try await vm.forgetReviewedSSHIdentity(for: request.device, matching: identity)
            XCTFail("A failed asynchronous deletion must be reported")
        } catch {
            XCTAssertEqual(error as? SSHKeychainStore.Failure, .keychain(errSecInteractionNotAllowed))
        }
        backend.failure = nil
        backend.requireBackgroundAccess = false
        XCTAssertEqual(try vm.trustedSSHIdentity(for: request.device), identity)
        backend.requireBackgroundAccess = true
        try await vm.forgetReviewedSSHIdentity(for: request.device, matching: identity)
        backend.requireBackgroundAccess = false
        XCTAssertNil(try keys.trustedKey(for: configuration))
        XCTAssertEqual(try keys.trustedKey(for: otherPort), identity)
        guard case .password(let secret)? = try store.getSSHCredentials(for: request.device) else {
            return XCTFail("Forgetting server approval must preserve account credentials")
        }
        XCTAssertEqual(secret, "synthetic-only")
        XCTAssertEqual(store.device(withID: request.device.id), request.device)
        try vm.forgetSSHIdentity(for: request.device, matching: identity)
        XCTAssertTrue(store.deleteDevice(request.device))
    }

    func testStaleReviewedIdentityCannotForgetAReplacementOrEditedConnection() throws {
        let suite = "test.aetherscreens.ssh.stale-forget." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keys = SSHKeychainStore(backend: FixtureSecretBackend())
        let store = TestStorage.make(userDefaults: defaults, sshKeychain: keys)
        let configuration = try SSHConfiguration(host: "ssh.invalid", username: "qa")
        let first = SSHHostKeyIdentity(key: NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey()).publicKey)
        let changed = SSHHostKeyIdentity(key: NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey()).publicKey)
        let device = RemoteDevice(name: "Stale review fixture", host: "rfb.invalid", sshConfiguration: configuration)
        store.addDevice(device)
        try keys.approve(first, for: configuration)
        try keys.forgetTrustedKey(for: configuration, matching: first)
        try keys.approve(changed, for: configuration)
        XCTAssertThrowsError(try store.forgetSSHIdentity(for: device, matching: first)) {
            XCTAssertEqual($0 as? SSHKeychainStore.Failure, .changedHostKey)
        }
        XCTAssertEqual(try keys.trustedKey(for: configuration), changed)
        var edited = device
        edited.sshConfiguration = try SSHConfiguration(host: "changed.invalid", username: "qa")
        store.updateDevice(edited)
        XCTAssertThrowsError(try store.forgetSSHIdentity(for: device, matching: changed)) {
            XCTAssertEqual($0 as? SSHKeychainStore.Failure, .credentialMismatch)
        }
        XCTAssertEqual(try keys.trustedKey(for: configuration), changed)
    }

    func testConnectionSaveFailureDoesNotPublishDeviceOrLoseExistingCredential() throws {
        let suite = "test.aetherscreens.ssh.form." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = FixtureSecretBackend()
        let keys = SSHKeychainStore(backend: backend)
        let store = TestStorage.make(userDefaults: defaults, sshKeychain: keys)
        let configuration = try SSHConfiguration(host: "ssh.invalid", username: "qa")
        let request = try XCTUnwrap(ConnectionRequest(host: "rfb.invalid", sshConfiguration: configuration,
                                                      sshCredentials: .password("synthetic-only")))
        backend.failure = .keychain(errSecInteractionNotAllowed)
        XCTAssertThrowsError(try store.saveConnection(request))
        XCTAssertTrue(store.devices.isEmpty)
        XCTAssertNil(defaults.data(forKey: DeviceStore.storageKey))
        backend.failure = nil
        try store.saveConnection(request)
        backend.failure = .keychain(errSecInteractionNotAllowed)
        var edited = request.device
        edited.sshConfiguration = nil
        XCTAssertThrowsError(try store.updateConnection(edited, password: nil, sshCredentials: nil))
        XCTAssertEqual(store.device(withID: edited.id)?.sshConfiguration, configuration)
        backend.failure = nil
        guard case .password(let secret)? = try keys.load(for: edited.id, configuration: configuration) else {
            return XCTFail("Original credential must remain after failed removal")
        }
        XCTAssertEqual(secret, "synthetic-only")
        XCTAssertTrue(store.deleteDevice(edited))
    }

    func testCredentialBindingAndFailedReplacementPreserveOldSecret() throws {
        let backend = FixtureSecretBackend()
        let store = SSHKeychainStore(backend: backend)
        let id = UUID()
        let configuration = try SSHConfiguration(host: "fixture.invalid", username: "qa")
        try store.save(.password("synthetic-old"), for: id, configuration: configuration)
        backend.failure = .keychain(errSecInteractionNotAllowed)
        XCTAssertThrowsError(try store.save(.password("synthetic-new"), for: id, configuration: configuration))
        backend.failure = nil
        guard case .password(let password) = try store.load(for: id, configuration: configuration) else {
            return XCTFail("Stored password missing")
        }
        XCTAssertEqual(password, "synthetic-old")
        let edited = try SSHConfiguration(host: "other.invalid", username: "qa")
        XCTAssertThrowsError(try store.load(for: id, configuration: edited)) {
            XCTAssertEqual($0 as? SSHKeychainStore.Failure, .credentialMismatch)
        }
        try store.deleteCredentials(for: id)
        XCTAssertNil(try store.load(for: id, configuration: configuration))
    }

    func testReadFailureIsReportedRatherThanMissingCredential() throws {
        let backend = FixtureSecretBackend(); backend.failure = .keychain(errSecAuthFailed)
        let store = SSHKeychainStore(backend: backend)
        let configuration = try SSHConfiguration(host: "fixture.invalid", username: "qa")
        XCTAssertThrowsError(try store.load(for: UUID(), configuration: configuration)) {
            XCTAssertEqual($0 as? SSHKeychainStore.Failure, .keychain(errSecAuthFailed))
        }
        XCTAssertThrowsError(try store.trustedKey(for: configuration))
    }

    func testApprovedHostKeyCannotBeSilentlyReplacedAndIsAccountIndependent() throws {
        let store = SSHKeychainStore(backend: FixtureSecretBackend())
        let first = SSHHostKeyIdentity(key: NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey()).publicKey)
        let changed = SSHHostKeyIdentity(key: NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey()).publicKey)
        let configuration = try SSHConfiguration(host: "Fixture.invalid", username: "qa")
        try store.approve(first, for: configuration)
        try store.approve(first, for: configuration)
        XCTAssertThrowsError(try store.approve(changed, for: configuration)) {
            XCTAssertEqual($0 as? SSHKeychainStore.Failure, .changedHostKey)
        }
        let otherAccount = try SSHConfiguration(host: "fixture.invalid", username: "other")
        XCTAssertEqual(try store.trustedKey(for: otherAccount), first)
        XCTAssertNil(try store.trustedKey(for: SSHConfiguration(host: "fixture.invalid", port: 2222, username: "qa")))
        try store.forgetTrustedKey(for: configuration)
        try store.approve(changed, for: configuration)
        XCTAssertEqual(try store.trustedKey(for: configuration), changed)
    }

    func testRealKeychainDurabilityAcrossStoreInstancesAndDeletion() throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_QA_REAL_KEYCHAIN"] == "1" else {
            throw XCTSkip("Set AETHERSCREENS_QA_REAL_KEYCHAIN=1 to test system Keychain durability with synthetic records")
        }
        let service = "test.aetherscreens.ssh." + UUID().uuidString
        let first = SSHKeychainStore(service: service)
        let second = SSHKeychainStore(service: service)
        let id = UUID()
        let configuration = try SSHConfiguration(host: "fixture.invalid", username: "qa")
        defer { try? first.deleteCredentials(for: id); try? first.forgetTrustedKey(for: configuration) }
        try first.save(.password("synthetic-keychain-only"), for: id, configuration: configuration)
        guard case .password(let password) = try second.load(for: id, configuration: configuration) else {
            return XCTFail("Credential was not durable")
        }
        XCTAssertEqual(password, "synthetic-keychain-only")
        let identity = SSHHostKeyIdentity(key: NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey()).publicKey)
        try first.approve(identity, for: configuration)
        XCTAssertEqual(try second.trustedKey(for: configuration), identity)
        try second.deleteCredentials(for: id)
        XCTAssertNil(try first.load(for: id, configuration: configuration))
    }

    func testDeviceMigrationAndConfigurationNeverEncodeSecrets() throws {
        let old = RemoteDevice(name: "Legacy", host: "fixture.invalid")
        XCTAssertNil(try JSONDecoder().decode(RemoteDevice.self, from: JSONEncoder().encode(old)).sshConfiguration)
        let configuration = try SSHConfiguration(host: "ssh.invalid", username: "ssh-account")
        var device = old; device.sshConfiguration = configuration
        let encoded = try JSONEncoder().encode(device)
        XCTAssertEqual(try JSONDecoder().decode(RemoteDevice.self, from: encoded), device)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("passphrase"))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("secret"))
        XCTAssertThrowsError(try SSHConfiguration(host: "user@host", username: "qa"))
        XCTAssertThrowsError(try SSHConfiguration(host: "host", port: 0, username: "qa"))
        let invalid = Data("{\"host\":\"host\",\"port\":0,\"username\":\"qa\",\"authentication\":\"password\",\"destinationHost\":\"127.0.0.1\"}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(SSHConfiguration.self, from: invalid))
    }

    @MainActor
    func testMissingSSHCredentialsNeverFallsBackToDirectRFB() async throws {
        let configuration = try SSHConfiguration(host: "ssh.invalid", username: "qa")
        let device = RemoteDevice(name: "SSH fixture", host: "rfb.invalid", sshConfiguration: configuration)
        let session = TestSession.make(device: device, password: nil, isTemporary: true)
        session.startSession()
        for _ in 0..<100 {
            if case .failed = session.sessionState { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard case .failed = session.sessionState else { return XCTFail("SSH configuration must not be ignored") }
        XCTAssertEqual(session.client.state, .disconnected)
    }

    func testDeviceDeletionRetainsRecordOnKeychainFailureThenRemovesCredential() throws {
        let suite = "test.aetherscreens.ssh.deletion." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = FixtureSecretBackend()
        let secrets = SSHKeychainStore(backend: backend)
        let store = TestStorage.make(userDefaults: defaults,
            keychain: KeychainStore(serviceName: suite, legacyServiceName: nil, backend: TestKeychainBackend()),
            sshKeychain: secrets)
        let configuration = try SSHConfiguration(host: "ssh.invalid", username: "qa")
        let device = RemoteDevice(name: "SSH deletion fixture", host: "rfb.invalid", sshConfiguration: configuration)
        store.addDevice(device)
        try secrets.save(.password("synthetic-only"), for: device.id, configuration: configuration)
        backend.failure = .keychain(errSecInteractionNotAllowed)
        XCTAssertFalse(store.deleteDevice(device))
        XCTAssertEqual(store.device(withID: device.id), device)
        backend.failure = nil
        XCTAssertNotNil(try secrets.load(for: device.id, configuration: configuration))
        XCTAssertTrue(store.deleteDevice(device))
        XCTAssertNil(store.device(withID: device.id))
        XCTAssertNil(try secrets.load(for: device.id, configuration: configuration))
    }
}

private final class FixtureSecretBackend: SSHSecretBackend {
    var requireBackgroundAccess = false
    var records: [String: Data] = [:]
    var failure: SSHKeychainStore.Failure?
    func read(account: String) throws -> Data? {
        if requireBackgroundAccess { XCTAssertFalse(Thread.isMainThread, "Keychain access must leave the UI thread free") }
        if let failure { throw failure }; return records[account]
    }
    func write(_ data: Data, account: String) throws { if let failure { throw failure }; records[account] = data }
    func insert(_ data: Data, account: String) throws {
        if let failure { throw failure }
        guard records[account] == nil else { throw SSHKeychainStore.Failure.keychain(errSecDuplicateItem) }
        records[account] = data
    }
    func delete(account: String) throws {
        if requireBackgroundAccess { XCTAssertFalse(Thread.isMainThread, "Keychain deletion must leave the UI thread free") }
        if let failure { throw failure }; records[account] = nil
    }
}
