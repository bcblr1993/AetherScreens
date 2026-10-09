import XCTest
@testable import AetherScreensCore

final class SSHHostTrustTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() {
        suite = "test.aetherscreens.ssh-trust." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    private func key(_ first: UInt8 = 1) throws -> SSHHostKey {
        var data = Data([0, 0, 0, 11]); data.append(Data("ssh-ed25519".utf8))
        data.append(Data([0, 0, 0, 32])); data.append(contentsOf: (0..<32).map { first &+ UInt8($0) })
        return try SSHHostKey(validatedKeyBlob: data)
    }

    func testFingerprintMatchesIndependentOpenSSHFixture() throws {
        XCTAssertEqual(try key().fingerprint, "SHA256:mKqU+0K8OhKmA8bBQi9Rz0Q5l7/g160hIP+rJYSTNj4")
        XCTAssertThrowsError(try SSHHostKey(validatedKeyBlob: Data()))
        XCTAssertThrowsError(try SSHHostKey(validatedKeyBlob: Data([255, 255, 255, 255, 0, 0, 0, 0])))
    }

    func testEndpointCanonicalizationAndPortIsolation() throws {
        let dns = try XCTUnwrap(SSHServerAddress(host: " Studio.local. "))
        XCTAssertEqual(dns.identity, SSHServerAddress(host: "studio.local")?.identity)
        XCTAssertEqual(SSHServerAddress(host: "[2001:db8::1]")?.identity,
                       SSHServerAddress(host: "2001:0db8:0:0:0:0:0:1")?.identity)
        XCTAssertNotEqual(dns.identity, SSHServerAddress(host: "studio.local", port: 2222)?.identity)
        for host in ["", "user@host", "ssh://host", "host:22", "two hosts", "[broken]"] {
            XCTAssertNil(SSHServerAddress(host: host))
        }
        XCTAssertNil(SSHServerAddress(host: "host", port: 0))
    }

    func testTrustPersistenceRequiresExplicitChangeDecisionAndRejectsStaleApproval() throws {
        let store = SSHHostTrustStore(defaults: defaults)
        let server = try XCTUnwrap(SSHServerAddress(host: "studio.local"))
        let old = try key(), replacement = try key(2), newer = try key(3)
        XCTAssertEqual(try store.assess(old, at: server), .unknown)
        try store.approve(old, at: server)
        let reloaded = SSHHostTrustStore(defaults: defaults)
        XCTAssertEqual(try reloaded.assess(old, at: server), .trusted)
        XCTAssertEqual(try reloaded.assess(replacement, at: server), .changed(previous: old))
        XCTAssertThrowsError(try reloaded.approve(replacement, at: server))
        XCTAssertEqual(try store.assess(old, at: server), .trusted)
        try reloaded.approve(replacement, at: server, replacing: old)
        XCTAssertThrowsError(try store.approve(newer, at: server, replacing: old))
        XCTAssertThrowsError(try store.forget(server, expected: old))
        XCTAssertEqual(try store.assess(replacement, at: server), .trusted)
        try store.forget(server, expected: replacement)
        XCTAssertEqual(try reloaded.assess(replacement, at: server), .unknown)
    }

    func testDifferentEndpointsNeverShareTrust() throws {
        let store = SSHHostTrustStore(defaults: defaults)
        let first = try XCTUnwrap(SSHServerAddress(host: "host"))
        let alternate = try XCTUnwrap(SSHServerAddress(host: "host", port: 2222))
        let other = try XCTUnwrap(SSHServerAddress(host: "other"))
        let key = try key()
        try store.approve(key, at: first)
        XCTAssertEqual(try store.assess(key, at: alternate), .unknown)
        XCTAssertEqual(try store.assess(key, at: other), .unknown)
    }

    func testConcurrentFirstUseDecisionsCannotSilentlyReplaceEachOther() throws {
        final class Results: @unchecked Sendable {
            let lock = NSLock()
            var successes = 0
            var stale = 0
            var unexpected = 0
            func record(_ error: Error?) {
                lock.lock(); defer { lock.unlock() }
                if error == nil { successes += 1 }
                else if error as? SSHHostTrustStore.Failure == .staleDecision { stale += 1 }
                else { unexpected += 1 }
            }
        }
        let server = try XCTUnwrap(SSHServerAddress(host: "host"))
        let keys = [try key(), try key(2)]
        let stores = [SSHHostTrustStore(defaults: defaults), SSHHostTrustStore(defaults: defaults)]
        let results = Results()
        DispatchQueue.concurrentPerform(iterations: 2) { index in
            do { try stores[index].approve(keys[index], at: server); results.record(nil) }
            catch { results.record(error) }
        }
        XCTAssertEqual(results.successes, 1)
        XCTAssertEqual(results.stale, 1)
        XCTAssertEqual(results.unexpected, 0)
        let assessments = try keys.map { try stores[0].assess($0, at: server) }
        XCTAssertEqual(assessments.filter { $0 == .trusted }.count, 1)
        XCTAssertFalse(assessments.contains(.unknown))
    }

    func testDamagedPersistenceFailsClosedAndIsNotOverwritten() throws {
        let server = try XCTUnwrap(SSHServerAddress(host: "host")), key = try key()
        let store = SSHHostTrustStore(defaults: defaults)
        for damaged: Any in ["wrong type", Data("not JSON".utf8), Data("{\"host\":{\"blob\":\"\"}}".utf8)] {
            defaults.set(damaged, forKey: SSHHostTrustStore.storageKey)
            XCTAssertThrowsError(try store.assess(key, at: server)) { XCTAssertEqual($0 as? SSHHostTrustStore.Failure, .damagedStorage) }
            XCTAssertThrowsError(try store.approve(key, at: server))
            XCTAssertThrowsError(try store.forget(server, expected: key))
            XCTAssertTrue((defaults.object(forKey: SSHHostTrustStore.storageKey) as? NSObject)?.isEqual(damaged) == true)
        }
    }

    func testSettingsValidateDecodedDataAndKeepOnlyPrivateKeyReference() throws {
        let server = try XCTUnwrap(SSHServerAddress(host: "studio.local"))
        let reference = UUID()
        let settings = try XCTUnwrap(SSHConnectionSettings(server: server, username: " user ", authentication: .privateKey(reference)))
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(SSHConnectionSettings.self, from: data), settings)
        XCTAssertEqual(settings.username, "user")
        XCTAssertEqual(settings.remoteHost, "127.0.0.1")
        XCTAssertNil(SSHConnectionSettings(server: server, username: ""))
        XCTAssertNil(SSHConnectionSettings(server: server, username: "user\u{0}name"))
        XCTAssertNil(SSHConnectionSettings(server: server, username: "user", remoteHost: "ssh://host"))
        XCTAssertThrowsError(try JSONDecoder().decode(SSHServerAddress.self, from: Data("{\"host\":\"host\",\"port\":0}".utf8)))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["username"] = ""
        XCTAssertThrowsError(try JSONDecoder().decode(SSHConnectionSettings.self, from: JSONSerialization.data(withJSONObject: object)))
    }
}
