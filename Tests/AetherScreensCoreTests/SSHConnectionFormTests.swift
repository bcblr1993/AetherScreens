import XCTest
import AetherScreensSSH
@testable import AetherScreensCore

final class SSHConnectionFormTests: XCTestCase {
    func testPrivateKeyFileReadBoundsActualContentsAndRejectsNonFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ssh-bounded-read-qa-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("fixture")
        let maximum = Data(repeating: 65, count: 65_536)
        try maximum.write(to: file)
        XCTAssertEqual(try SSHConnectionDraft.readPrivateKey(from: file), maximum)
        try Data(repeating: 65, count: 2 * 1024 * 1024).write(to: file)
        XCTAssertThrowsError(try SSHConnectionDraft.readPrivateKey(from: file))
        try Data().write(to: file)
        XCTAssertThrowsError(try SSHConnectionDraft.readPrivateKey(from: file))
        XCTAssertThrowsError(try SSHConnectionDraft.readPrivateKey(from: directory))
        XCTAssertThrowsError(try SSHConnectionDraft.readPrivateKey(from: directory.appendingPathComponent("missing")))
    }

    func testPrivateKeyImportAcceptsRealEncryptedAndPlainKeysAndPreservesSelectionOnFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ssh-import-qa-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func generate(type: String, name: String, passphrase: String) throws -> Data {
            let process = Process()
            let path = directory.appendingPathComponent(name)
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
            process.arguments = ["-q", "-t", type, "-N", passphrase, "-C", "qa-fixture", "-f", path.path]
            if type == "rsa" { process.arguments! += ["-b", "2048"] }
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            return try Data(contentsOf: path)
        }
        var draft = SSHConnectionDraft()
        let plain = try generate(type: "ed25519", name: "plain", passphrase: "")
        try draft.importPrivateKey(plain)
        XCTAssertEqual(Data(draft.privateKey.utf8), plain)
        let encrypted = try generate(type: "ed25519", name: "encrypted", passphrase: "synthetic-key-passphrase")
        draft.passphrase = "previous-fixture-passphrase"
        try draft.importPrivateKey(encrypted)
        XCTAssertEqual(Data(draft.privateKey.utf8), encrypted)
        XCTAssertTrue(draft.passphrase.isEmpty, "A replacement key must not inherit the previous key's passphrase")
        draft.passphrase = "synthetic-key-passphrase"
        let rsa = try generate(type: "rsa", name: "unsupported", passphrase: "")
        let plainLines = String(decoding: plain, as: UTF8.self).split(whereSeparator: { $0.isNewline })
        var corrupt = try XCTUnwrap(Data(base64Encoded: plainLines.dropFirst().dropLast().joined()))
        var offset = "openssh-key-v1\0".utf8.count
        func skipField() {
            let length = corrupt[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
            offset += 4 + length
        }
        for _ in 0..<3 { skipField() }
        offset += 4 // one-key count
        skipField() // public key
        offset += 4 // private block length
        corrupt[offset] ^= 1 // mismatched private check integers, with valid container metadata
        let corruptPlain = Data(("-----BEGIN OPENSSH PRIVATE KEY-----\n" + corrupt.base64EncodedString()
            + "\n-----END OPENSSH PRIVATE KEY-----\n").utf8)
        for invalid in [Data(), Data([0xff]), Data(repeating: 65, count: 65_537), rsa, corruptPlain,
                        Data("-----BEGIN OPENSSH PRIVATE KEY-----\nAAAA\n-----END OPENSSH PRIVATE KEY-----".utf8),
                        encrypted.prefix(encrypted.count / 2)] {
            XCTAssertThrowsError(try draft.importPrivateKey(invalid))
            XCTAssertEqual(Data(draft.privateKey.utf8), encrypted, "Failed replacement must preserve the selected private key")
            XCTAssertEqual(draft.passphrase, "synthetic-key-passphrase")
        }
    }

    func testDraftSeparatesEndpointAndCredentialValidation() throws {
        var draft = SSHConnectionDraft()
        XCTAssertTrue(draft.valid(defaultHost: "studio.local"))
        draft.enabled = true
        draft.username = " qa-user "
        XCTAssertFalse(draft.valid(defaultHost: "studio.local"))
        draft.password = " secret "
        XCTAssertTrue(draft.valid(defaultHost: "studio.local"))
        let configuration = try XCTUnwrap(draft.configuration(defaultHost: "studio.local"))
        XCTAssertEqual(configuration.host, "studio.local")
        XCTAssertEqual(configuration.username, "qa-user")
        draft.port = "65536"
        XCTAssertFalse(draft.valid(defaultHost: "studio.local"))
        draft.port = "22"
        draft.authentication = .ed25519
        XCTAssertFalse(draft.valid(defaultHost: "studio.local"), "Password cannot authorize private-key authentication")
        draft.keepSavedCredential = true
        XCTAssertFalse(draft.valid(defaultHost: "studio.local"))
        XCTAssertTrue(draft.valid(defaultHost: "studio.local", editing: true))
    }

    func testRequestRequiresMatchingCredentialsAndDoesNotEncodeSecrets() throws {
        let configuration = try SSHConfiguration(host: "gateway.local", username: "qa")
        XCTAssertNil(ConnectionRequest(host: "studio.local", sshConfiguration: configuration))
        XCTAssertNil(ConnectionRequest(host: "studio.local", sshCredentials: .password("qa-only")))
        XCTAssertNil(ConnectionRequest(host: "studio.local", sshConfiguration: configuration,
                                       sshCredentials: .ed25519PrivateKey("invalid-key", passphrase: nil)))
        let request = try XCTUnwrap(ConnectionRequest(host: "studio.local", password: "vnc-test-only",
                                sshConfiguration: configuration, sshCredentials: .password("ssh-test-only")))
        let metadata = String(decoding: try JSONEncoder().encode(request.device), as: UTF8.self)
        XCTAssertFalse(metadata.contains("vnc-test-only"))
        XCTAssertFalse(metadata.contains("ssh-test-only"))
        XCTAssertEqual(request.device.host, "studio.local")
        XCTAssertEqual(request.device.sshConfiguration?.host, "gateway.local")
    }

    @MainActor
    func testTemporaryVersusSavedAndEditedSSHCredentials() throws {
        let id = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ssh-form-qa." + id))
        defer { defaults.removePersistentDomain(forName: "ssh-form-qa." + id) }
        let keys = TestStorage.sshKeychain()
        let store = TestStorage.make(userDefaults: defaults, sshKeychain: keys)
        let discovery = BonjourDiscoveryService()
        defer { discovery.stopDiscovery() }
        let vm = DeviceListViewModel(store: store, bonjourService: discovery)
        let configuration = try SSHConfiguration(host: "gateway.invalid", username: "qa")
        let request = try XCTUnwrap(ConnectionRequest(host: "studio.invalid", sshConfiguration: configuration,
                                                      sshCredentials: .password("synthetic-only")))
        defer { _ = store.deleteDevice(request.device) }
        let temporary = try vm.prepareQuickSession(request, saveComputer: false)
        XCTAssertTrue(temporary.isTemporary)
        XCTAssertTrue(store.devices.isEmpty)
        XCTAssertNil(try keys.load(for: request.device.id, configuration: configuration))
        let saved = try vm.prepareQuickSession(request, saveComputer: true)
        XCTAssertFalse(saved.isTemporary)
        guard case .password(let password)? = try store.getSSHCredentials(for: request.device) else { return XCTFail("Missing saved credential") }
        XCTAssertEqual(password, "synthetic-only")
        var edited = request.device
        edited.sshConfiguration = try SSHConfiguration(host: "changed.invalid", username: "qa")
        XCTAssertThrowsError(try vm.updateConnection(edited, password: nil, sshCredentials: nil))
        XCTAssertEqual(store.device(withID: edited.id)?.sshConfiguration, configuration)
        try vm.updateConnection(edited, password: nil, sshCredentials: .password("replacement-only"))
        XCTAssertEqual(store.device(withID: edited.id)?.sshConfiguration, edited.sshConfiguration)
        edited.sshConfiguration = nil
        try vm.updateConnection(edited, password: nil, sshCredentials: nil)
        XCTAssertNil(try keys.load(for: edited.id, configuration: configuration))
    }
}
