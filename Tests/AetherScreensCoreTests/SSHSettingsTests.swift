import XCTest
import Security
import CryptoKit
@testable import AetherScreensCore

final class SSHSettingsTests: XCTestCase {
    private final class Vault: SSHKeychainAccess {
        var values: [String: Data] = [:]
        var writeStatus: OSStatus = errSecSuccess
        var deleteStatus: OSStatus = errSecSuccess
        var writes = 0
        var readStatus: OSStatus?
        func accounts(_ query: [String: Any]) -> (OSStatus, [String]?) {
            if let readStatus { return (readStatus, nil) }
            return (errSecSuccess, Array(values.keys))
        }
        func account(_ query: [String: Any]) -> String { query[kSecAttrAccount as String] as! String }
        func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
            guard writeStatus == errSecSuccess else { return writeStatus }
            guard values[account(query)] != nil else { return errSecItemNotFound }
            writes += 1; values[account(query)] = attributes[kSecValueData as String] as? Data
            return errSecSuccess
        }
        func add(_ attributes: [String: Any]) -> OSStatus {
            guard writeStatus == errSecSuccess else { return writeStatus }
            writes += 1; values[account(attributes)] = attributes[kSecValueData as String] as? Data
            return errSecSuccess
        }
        func copy(_ query: [String: Any]) -> (OSStatus, Data?) {
            if let readStatus { return (readStatus, nil) }
            let value = values[account(query)]
            return (value == nil ? errSecItemNotFound : errSecSuccess, value)
        }
        func delete(_ query: [String: Any]) -> OSStatus {
            guard deleteStatus == errSecSuccess else { return deleteStatus }
            values.removeValue(forKey: account(query)); return errSecSuccess
        }
    }

    @MainActor
    private func environment() throws -> (DeviceListViewModel, DeviceStore, SSHCredentialStore, Vault, UserDefaults) {
        let suite = "test.ssh.settings." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let vault = Vault(), credentials = SSHCredentialStore(service: "settings-qa", access: vault)
        let store = DeviceStore(userDefaults: defaults, sshCredentials: credentials)
        let discovery = BonjourDiscoveryService()
        let model = DeviceListViewModel(store: store, bonjourService: discovery)
        addTeardownBlock { discovery.stopDiscovery(); defaults.removePersistentDomain(forName: suite) }
        return (model, store, credentials, vault, defaults)
    }

    private func settings(host: String = "ssh.example", username: String = "qa", target: String = "127.0.0.1") throws -> SSHConnectionSettings {
        try XCTUnwrap(SSHConnectionSettings(server: XCTUnwrap(SSHServerAddress(host: host)), username: username, remoteHost: target))
    }

    func testDraftValidatesAndPreservesExistingKeyReferenceWithoutSecrets() throws {
        var draft = SSHConnectionDraft()
        XCTAssertTrue(draft.isValid)
        draft.enabled = true
        XCTAssertFalse(draft.isValid)
        draft.serverHost = "[::1]"; draft.username = " qa "
        XCTAssertTrue(draft.isValid)
        XCTAssertEqual(draft.settings?.username, "qa")
        for port in ["0", "65536", "bad"] { draft.port = port; XCTAssertFalse(draft.isValid) }
        draft.port = "22"; draft.remoteHost = "vnc://invalid"
        XCTAssertFalse(draft.isValid)
        let keyID = UUID()
        let configured = try XCTUnwrap(SSHConnectionSettings(server: XCTUnwrap(SSHServerAddress(host: "ssh.example")),
            username: "qa", authentication: .privateKey(keyID)))
        let restored = SSHConnectionDraft(settings: configured)
        XCTAssertEqual(restored.settings, configured)
        XCTAssertNil(restored.passwordToSave)
    }

    @MainActor
    func testImportedPrivateKeyIsValidatedAndSavedOutsideDeviceDefaults() throws {
        let (model, store, credentials, vault, defaults) = try environment()
        let data = Data(P256.Signing.PrivateKey().pemRepresentation.utf8)
        var draft = SSHConnectionDraft(settings: try settings())
        draft.authenticationMode = .privateKey
        XCTAssertFalse(draft.isValid)
        try draft.importPrivateKey(data)
        let reference = try XCTUnwrap(draft.keyReference)
        XCTAssertThrowsError(try draft.importPrivateKey(Data("damaged QA file".utf8)))
        XCTAssertEqual(draft.keyReference, reference, "Invalid replacement must preserve the prior selection")
        XCTAssertEqual(draft.privateKeyToSave, data)
        XCTAssertNotNil(draft.keyFingerprint)
        let request = try XCTUnwrap(ConnectionRequest(host: "desktop.invalid", ssh: draft.settings, sshPrivateKey: draft.privateKeyToSave))
        vault.writeStatus = errSecInteractionNotAllowed
        XCTAssertThrowsError(try model.prepareQuickSession(request, saveComputer: true))
        XCTAssertTrue(store.devices.isEmpty)
        XCTAssertNil(defaults.data(forKey: DeviceStore.storageKey))
        let temporary = try model.prepareQuickSession(request, saveComputer: false)
        temporary.endSession()
        XCTAssertEqual(vault.writes, 0)
        vault.writeStatus = errSecSuccess
        let saved = try model.prepareQuickSession(request, saveComputer: true)
        saved.endSession()
        XCTAssertEqual(try credentials.load(kind: .privateKey, reference: reference), data)
        let json = String(decoding: try XCTUnwrap(defaults.data(forKey: DeviceStore.storageKey)), as: UTF8.self)
        XCTAssertFalse(json.contains("PRIVATE KEY"))
        XCTAssertFalse(json.contains(data.base64EncodedString()))
        XCTAssertEqual(store.devices.first?.ssh?.authentication, .privateKey(reference))
        // Renaming a saved computer with an existing key does not overwrite it.
        var updated = request.device; updated.name = "Renamed QA"
        try model.saveConfiguredDevice(updated, password: nil, sshPassword: nil)
        XCTAssertEqual(try credentials.load(kind: .privateKey, reference: reference), data)
        XCTAssertThrowsError(try model.saveConfiguredDevice(updated, password: nil, sshPassword: nil, sshPrivateKey: data))
    }

    @MainActor
    func testSavedKeyReuseDeduplicatesAndPreservesSelectionOnVaultFailure() throws {
        let (model, store, credentials, vault, _) = try environment()
        let reference = UUID()
        let configured = try XCTUnwrap(SSHConnectionSettings(server: settings().server,
            username: "qa", authentication: .privateKey(reference)))
        let data = Data(P256.Signing.PrivateKey().pemRepresentation.utf8)
        try credentials.save(data, kind: .privateKey, reference: reference)
        for name in ["First QA computer", "Shared QA computer"] {
            var device = try XCTUnwrap(ConnectionRequest(host: "desktop.invalid", name: name, ssh: configured)).device
            device.name = name
            store.addDevice(device)
        }
        model.reload()
        XCTAssertEqual(model.savedSSHKeys.count, 1)
        let key = try XCTUnwrap(model.savedSSHKeys.first)
        var draft = SSHConnectionDraft(settings: try settings(host: "other.example", username: "other"))
        try draft.importPrivateKey(Data(P384.Signing.PrivateKey().pemRepresentation.utf8))
        let previous = draft.keyReference
        vault.readStatus = errSecInteractionNotAllowed
        XCTAssertThrowsError(try model.selectSavedSSHKey(key, draft: &draft))
        XCTAssertEqual(draft.keyReference, previous)
        XCTAssertNotNil(draft.privateKeyToSave)
        vault.readStatus = nil
        let writes = vault.writes
        try model.selectSavedSSHKey(key, draft: &draft)
        XCTAssertEqual(draft.keyReference, reference)
        XCTAssertEqual(draft.serverHost, "other.example")
        XCTAssertEqual(draft.username, "other")
        XCTAssertNil(draft.privateKeyData)
        XCTAssertEqual(vault.writes, writes)
        let reused = try XCTUnwrap(ConnectionRequest(host: "other.invalid", ssh: draft.settings))
        try model.saveConfiguredDevice(reused.device, password: nil, sshPassword: nil)
        XCTAssertEqual(vault.writes, writes, "Saving a reused key must not rewrite its secret")
        try credentials.remove(kind: .privateKey, reference: reference)
        XCTAssertThrowsError(try model.selectSavedSSHKey(key, draft: &draft))
        XCTAssertEqual(draft.keyReference, reference)
        let unsaved = try XCTUnwrap(ConnectionRequest(host: "missing.invalid", ssh: draft.settings))
        let count = store.devices.count
        XCTAssertThrowsError(try model.saveConfiguredDevice(unsaved.device, password: nil, sshPassword: nil))
        XCTAssertEqual(store.devices.count, count, "A missing reused key must not persist a computer")
    }

    @MainActor
    func testStandaloneKeyLibraryProtectsSavedAndOpenSessionReferences() throws {
        let (model, store, credentials, vault, defaults) = try environment()
        let data = Data(P256.Signing.PrivateKey().pemRepresentation.utf8)
        let key = try model.importManagedSSHKey(data)
        XCTAssertTrue(store.devices.isEmpty)
        XCTAssertNil(defaults.data(forKey: DeviceStore.storageKey))
        XCTAssertEqual(try model.managedSSHKeys().first?.id, key.id)
        let choice = try XCTUnwrap(model.savedSSHKeys.first)
        XCTAssertEqual(choice.id, key.id)
        var draft = SSHConnectionDraft()
        try model.selectSavedSSHKey(choice, draft: &draft)
        XCTAssertEqual(draft.keyReference, key.id)
        XCTAssertEqual(draft.keyFingerprint, key.fingerprint)
        XCTAssertNil(draft.privateKeyData)
        let configured = try XCTUnwrap(SSHConnectionSettings(server: settings().server,
            username: "qa", authentication: .privateKey(key.id)))
        let device = try XCTUnwrap(ConnectionRequest(host: "desktop.invalid", name: "Key user", ssh: configured)).device
        let sessions = SessionRegistry()
        let session = SessionViewModel(device: device, password: nil)
        let sessionID = sessions.register(session)
        XCTAssertThrowsError(try model.removeManagedSSHKey(key.id, sessions: sessions))
        _ = sessions.remove(sessionID)
        store.addDevice(device)
        XCTAssertEqual(try model.managedSSHKeys().first?.computers, ["Key user"])
        XCTAssertThrowsError(try model.removeManagedSSHKey(key.id, sessions: sessions))
        XCTAssertEqual(try credentials.load(kind: .privateKey, reference: key.id), data)
        XCTAssertTrue(store.deleteDevice(device))
        vault.deleteStatus = errSecInteractionNotAllowed
        XCTAssertThrowsError(try model.removeManagedSSHKey(key.id, sessions: sessions))
        vault.deleteStatus = errSecSuccess
        try model.removeManagedSSHKey(key.id, sessions: sessions)
        XCTAssertTrue(try model.managedSSHKeys().isEmpty)
    }

    @MainActor
    func testKeyNamesPersistWithoutReplacingSecretsAndDeniedRenameLeavesMetadataIntact() throws {
        let (model, store, credentials, vault, defaults) = try environment()
        let data = Data(P256.Signing.PrivateKey().pemRepresentation.utf8)
        let key = try model.importManagedSSHKey(data)
        try model.renameManagedSSHKey(key.id, name: "  Work Mac  ")
        let reopened = DeviceListViewModel(store: store)
        XCTAssertEqual(try reopened.managedSSHKeys().first?.name, "Work Mac")
        XCTAssertEqual(reopened.savedSSHKeys.first?.name, "Work Mac")
        XCTAssertEqual(try credentials.load(kind: .privateKey, reference: key.id), data)
        let names = try XCTUnwrap(defaults.dictionary(forKey: DeviceStore.sshKeyNamesStorageKey) as? [String: String])
        XCTAssertEqual(names, [key.id.uuidString: "Work Mac"])
        vault.readStatus = errSecInteractionNotAllowed
        XCTAssertThrowsError(try model.renameManagedSSHKey(key.id, name: "Changed"))
        XCTAssertEqual(store.sshKeyName(for: key.id), "Work Mac")
        vault.readStatus = nil
        try model.renameManagedSSHKey(key.id, name: String(repeating: "a", count: 200))
        XCTAssertEqual(store.sshKeyName(for: key.id)?.count, 120)
        try model.renameManagedSSHKey(key.id, name: " ")
        XCTAssertNil(store.sshKeyName(for: key.id))
        try model.renameManagedSSHKey(key.id, name: "Unused")
        try model.removeManagedSSHKey(key.id, sessions: SessionRegistry())
        XCTAssertNil(defaults.dictionary(forKey: DeviceStore.sshKeyNamesStorageKey))
        XCTAssertThrowsError(try model.renameManagedSSHKey(key.id, name: "Gone"))
    }

    @MainActor
    func testStandaloneKeyLibraryPreservesInvalidEntriesAndRejectsDeniedImport() throws {
        let (model, _, credentials, vault, _) = try environment()
        let id = UUID()
        try credentials.save(Data("broken QA key".utf8), kind: .privateKey, reference: id)
        let entry = try XCTUnwrap(model.managedSSHKeys().first)
        XCTAssertEqual(entry.id, id)
        XCTAssertNil(entry.fingerprint)
        XCTAssertNotNil(entry.problem)
        let before = vault.values
        vault.writeStatus = errSecInteractionNotAllowed
        XCTAssertThrowsError(try model.importManagedSSHKey(Data(P256.Signing.PrivateKey().pemRepresentation.utf8)))
        XCTAssertEqual(vault.values, before)
        vault.readStatus = errSecInteractionNotAllowed
        XCTAssertThrowsError(try model.managedSSHKeys())
    }

    @MainActor
    func testExportReturnsSelectedOriginalKeyWithoutChangingPersistence() throws {
        let (model, _, _, vault, defaults) = try environment()
        let data = Data(P256.Signing.PrivateKey().pemRepresentation.utf8)
        let key = try model.importManagedSSHKey(data)
        let writes = vault.writes
        let before = defaults.dictionaryRepresentation()
        let exported = try model.exportManagedSSHKey(key.id, expectedFingerprint: XCTUnwrap(key.fingerprint))
        XCTAssertTrue(exported == data, "Export must preserve the selected key bytes")
        XCTAssertEqual(vault.writes, writes)
        XCTAssertTrue(NSDictionary(dictionary: defaults.dictionaryRepresentation()).isEqual(to: before))
    }

    @MainActor
    func testExportRejectsChangedMissingAndDeniedKeys() throws {
        let (model, _, credentials, vault, _) = try environment()
        let key = try model.importManagedSSHKey(Data(P256.Signing.PrivateKey().pemRepresentation.utf8))
        let fingerprint = try XCTUnwrap(key.fingerprint)
        try credentials.save(Data(P256.Signing.PrivateKey().pemRepresentation.utf8), kind: .privateKey, reference: key.id)
        XCTAssertThrowsError(try model.exportManagedSSHKey(key.id, expectedFingerprint: fingerprint)) {
            guard case .changed? = $0 as? DeviceListViewModel.KeyManagementFailure else { return XCTFail("Expected changed identity rejection") }
        }
        vault.readStatus = errSecInteractionNotAllowed
        XCTAssertThrowsError(try model.exportManagedSSHKey(key.id, expectedFingerprint: fingerprint)) {
            XCTAssertEqual(($0 as? SSHCredentialStore.Failure)?.status, errSecInteractionNotAllowed)
        }
        vault.readStatus = nil
        try credentials.remove(kind: .privateKey, reference: key.id)
        XCTAssertThrowsError(try model.exportManagedSSHKey(key.id, expectedFingerprint: fingerprint)) {
            XCTAssertEqual($0 as? SSHPrivateKey.Failure, .missing)
        }
    }

    @MainActor
    func testExportRejectsCorruptVaultMaterial() throws {
        let (model, _, credentials, _, _) = try environment()
        let reference = UUID()
        try credentials.save(Data("invalid QA material".utf8), kind: .privateKey, reference: reference)
        XCTAssertThrowsError(try model.exportManagedSSHKey(reference, expectedFingerprint: "QA fingerprint")) {
            XCTAssertEqual($0 as? SSHPrivateKey.Failure, .invalid)
        }
    }

    func testExportDocumentWritesOriginalBytesWithPrivateLocalPermissions() throws {
        let data = Data(P256.Signing.PrivateKey().pemRepresentation.utf8)
        let document = try SSHPrivateKeyDocument(data: data)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aetherscreens-export-qa-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("qa-private-key.txt")
        try document.makeFileWrapper().write(to: destination, options: .atomic, originalContentsURL: nil)
        XCTAssertTrue(try Data(contentsOf: destination) == data, "No key content may be altered during export")
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertThrowsError(try SSHPrivateKeyDocument(data: Data(repeating: 0, count: SSHPrivateKey.maximumSize + 1))) {
            XCTAssertEqual($0 as? SSHPrivateKey.Failure, .tooLarge)
        }
    }

    @MainActor
    func testSavedPrivateKeyEditorReadsFingerprintWithoutStagingAReplacement() throws {
        let (model, _, credentials, vault, _) = try environment()
        let reference = UUID()
        let configured = try XCTUnwrap(SSHConnectionSettings(server: settings().server,
            username: "qa", authentication: .privateKey(reference)))
        XCTAssertThrowsError(try model.sshKeyFingerprint(for: configured)) {
            XCTAssertEqual($0 as? SSHPrivateKey.Failure, .missing)
        }
        let data = Data(P256.Signing.PrivateKey().pemRepresentation.utf8)
        try credentials.save(data, kind: .privateKey, reference: reference)
        let fingerprint = try XCTUnwrap(model.sshKeyFingerprint(for: configured))
        let draft = SSHConnectionDraft(settings: configured, keyFingerprint: fingerprint)
        XCTAssertEqual(draft.keyFingerprint, try SSHPrivateKey.fingerprint(SSHPrivateKey.decode(data)))
        XCTAssertEqual(draft.keyReference, reference)
        XCTAssertEqual(draft.settings, configured)
        XCTAssertNil(draft.privateKeyData)
        XCTAssertNil(draft.privateKeyToSave)
        vault.readStatus = errSecInteractionNotAllowed
        XCTAssertThrowsError(try model.sshKeyFingerprint(for: configured))
        XCTAssertNil(try model.sshKeyFingerprint(for: settings()))
    }

    @MainActor
    func testSavedQuickConnectionKeepsCredentialIdentityAndExcludesSecretsFromDefaults() throws {
        let (model, store, credentials, _, defaults) = try environment()
        let request = try XCTUnwrap(ConnectionRequest(host: "desktop.invalid", ssh: settings(), sshPassword: "QA SSH secret"))
        let session = try model.prepareQuickSession(request, saveComputer: true)
        defer { session.endSession() }
        XCTAssertEqual(store.devices.first?.id, request.device.id)
        XCTAssertEqual(try credentials.load(kind: .password, reference: request.device.id), Data("QA SSH secret".utf8))
        let serialized = try XCTUnwrap(defaults.data(forKey: DeviceStore.storageKey))
        XCTAssertFalse(String(decoding: serialized, as: UTF8.self).contains("QA SSH secret"))
        XCTAssertEqual(try JSONDecoder().decode([RemoteDevice].self, from: serialized).first?.ssh, request.device.ssh)
        XCTAssertFalse(session.isTemporary)
    }

    @MainActor
    func testTemporaryQuickConnectionNeverWritesVaultOrDefaults() throws {
        let (model, store, _, vault, defaults) = try environment()
        vault.writeStatus = errSecInteractionNotAllowed
        let request = try XCTUnwrap(ConnectionRequest(host: "desktop.invalid", ssh: settings(), sshPassword: "temporary QA"))
        let session = try model.prepareQuickSession(request, saveComputer: false)
        defer { session.endSession() }
        XCTAssertTrue(session.isTemporary)
        XCTAssertTrue(store.devices.isEmpty)
        XCTAssertNil(defaults.data(forKey: DeviceStore.storageKey))
        XCTAssertEqual(vault.writes, 0)
    }

    @MainActor
    func testDeniedSaveKeepsExistingConfigurationAndPassword() throws {
        let (model, store, credentials, vault, _) = try environment()
        let original = RemoteDevice(name: "Existing QA", host: "desktop.invalid", ssh: try settings())
        try model.saveConfiguredDevice(original, password: nil, sshPassword: "original QA")
        var updated = original; updated.name = "Changed QA"
        vault.writeStatus = errSecInteractionNotAllowed
        XCTAssertThrowsError(try model.saveConfiguredDevice(updated, password: nil, sshPassword: "replacement QA"))
        XCTAssertEqual(store.devices, [original])
        XCTAssertEqual(try credentials.load(kind: .password, reference: original.id), Data("original QA".utf8))
    }

    @MainActor
    func testChangedLoginClearsOldPasswordButTargetAndCanonicalHostChangesPreserveIt() throws {
        let (model, store, credentials, vault, _) = try environment()
        var device = RemoteDevice(name: "Login QA", host: "desktop.invalid", ssh: try settings())
        try model.saveConfiguredDevice(device, password: nil, sshPassword: "original QA")
        device.ssh = try settings(host: "SSH.EXAMPLE.", target: "other-desktop.example")
        try model.saveConfiguredDevice(device, password: nil, sshPassword: nil)
        XCTAssertNotNil(try credentials.load(kind: .password, reference: device.id))
        let before = device
        device.ssh = try settings(username: "another-user")
        vault.deleteStatus = errSecInteractionNotAllowed
        XCTAssertThrowsError(try model.saveConfiguredDevice(device, password: nil, sshPassword: nil))
        XCTAssertEqual(store.devices, [before])
        vault.deleteStatus = errSecSuccess
        try model.saveConfiguredDevice(device, password: nil, sshPassword: nil)
        XCTAssertNil(try credentials.load(kind: .password, reference: device.id))
    }

    @MainActor
    func testDeviceDeletionRequiresPasswordRemovalAndPreservesSharedPrivateKeys() throws {
        let (model, store, credentials, vault, _) = try environment()
        let device = RemoteDevice(name: "Delete QA", host: "desktop.invalid", ssh: try settings())
        try model.saveConfiguredDevice(device, password: nil, sshPassword: "delete QA")
        let key = UUID()
        try credentials.save(Data([1, 2, 3]), kind: .privateKey, reference: key)
        vault.deleteStatus = errSecInteractionNotAllowed
        model.deleteDevice(device)
        XCTAssertEqual(store.devices, [device])
        XCTAssertNotNil(model.errorMessage)
        vault.deleteStatus = errSecSuccess
        model.deleteDevice(device)
        XCTAssertTrue(store.devices.isEmpty)
        XCTAssertNil(try credentials.load(kind: .password, reference: device.id))
        XCTAssertNotNil(try credentials.load(kind: .privateKey, reference: key))
    }
}
