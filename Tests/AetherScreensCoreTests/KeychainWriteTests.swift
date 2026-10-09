import XCTest
import Security
@testable import AetherScreensCore

final class KeychainWriteTests: XCTestCase {
    func testDeviceConfigurationPersistsButFailedCredentialSaveIsReported() throws {
        let suite = "test.aetherscreens.denied-save.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = KeychainStore(serviceName: suite, writeOverride: { _, _, _ in false })
        let store = DeviceStore(userDefaults: defaults, keychain: keychain)
        let device = RemoteDevice(name: "Denied-save QA", host: "qa.invalid")
        XCTAssertFalse(store.addDevice(device, password: "synthetic"))
        XCTAssertEqual(store.devices.map(\.id), [device.id])
        XCTAssertNotNil(defaults.data(forKey: DeviceStore.storageKey))
        XCTAssertEqual(store.getPassword(for: device), "synthetic", "Current-process fallback remains available")
        XCTAssertTrue(store.updateDevice(device), "No credential write was requested")
        XCTAssertFalse(store.updateDevice(device, password: "replacement"))
    }

    @MainActor
    func testSessionReportsDeniedRememberWithoutDiscardingEnteredPassword() throws {
        let suite = "test.aetherscreens.session-denied.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DeviceStore(userDefaults: defaults,
            keychain: KeychainStore(serviceName: suite, writeOverride: { _, _, _ in false }))
        let device = RemoteDevice(name: "Credential QA", host: "qa.invalid", authMethod: .vncPassword)
        store.addDevice(device)
        let session = SessionViewModel(device: device, password: nil, deviceStore: store)
        session.submitPassword("synthetic", rememberInKeychain: true)
        XCTAssertNotNil(session.passwordSaveNotice)
        XCTAssertEqual(session.client.password, "synthetic")
        XCTAssertFalse(session.isPromptingPassword)
        session.submitPassword("next", rememberInKeychain: false)
        XCTAssertNil(session.passwordSaveNotice)
        XCTAssertEqual(session.client.password, "next")
    }

    func testDeniedLegacyMigrationRetainsSourceAndReturnsUsablePassword() {
        let payload = Data("synthetic-legacy".utf8)
        var deleted: [String] = []
        var writes = 0
        let store = KeychainStore(serviceName: "current", legacyServiceName: "legacy",
            readOverride: { service, _ in service == "legacy" ? payload : nil },
            deleteOverride: { service, _ in deleted.append(service); return errSecSuccess },
            writeOverride: { _, _, _ in writes += 1; return false })
        XCTAssertEqual(store.loadPassword(forKey: "device"), "synthetic-legacy")
        XCTAssertEqual(store.loadPassword(forKey: "device"), "synthetic-legacy")
        XCTAssertEqual(writes, 1, "The current-process cache remains usable after denied migration")
        XCTAssertTrue(deleted.isEmpty, "Failed destination persistence must never delete the source")
    }

    func testLegacySourceDeletionFollowsSuccessfulDestinationPersistence() {
        let payload = Data("synthetic-legacy".utf8)
        var operations: [String] = []
        let store = KeychainStore(serviceName: "current", legacyServiceName: "legacy",
            readOverride: { service, _ in service == "legacy" ? payload : nil },
            deleteOverride: { service, _ in operations.append("delete-" + service); return errSecSuccess },
            writeOverride: { data, service, _ in
                XCTAssertEqual(data, payload)
                operations.append("write-" + service)
                return true
            })
        XCTAssertEqual(store.loadPassword(forKey: "device"), "synthetic-legacy")
        XCTAssertEqual(operations, ["write-current", "delete-legacy"])
    }

    func testLockedUpdateDoesNotAttemptReplacement() {
        var added = false
        XCTAssertEqual(KeychainStore.upsert(update: { errSecInteractionNotAllowed },
            add: { added = true; return errSecSuccess }), errSecInteractionNotAllowed)
        XCTAssertFalse(added)
    }
    func testSuccessfulUpdateDoesNotAddDuplicate() {
        XCTAssertEqual(KeychainStore.upsert(update: { errSecSuccess },
            add: { XCTFail("Existing item must update in place"); return errSecDuplicateItem }), errSecSuccess)
    }
    func testMissingItemAddsAndDuplicateRaceRetriesUpdate() {
        var updates = 0
        var adds = 0
        XCTAssertEqual(KeychainStore.upsert(update: {
            updates += 1
            return updates == 1 ? errSecItemNotFound : errSecSuccess
        }, add: { adds += 1; return errSecDuplicateItem }), errSecSuccess)
        XCTAssertEqual(updates, 2)
        XCTAssertEqual(adds, 1)
    }
    func testMissingItemAddFailureRemainsFailure() {
        XCTAssertEqual(KeychainStore.upsert(update: { errSecItemNotFound },
            add: { errSecInteractionNotAllowed }), errSecInteractionNotAllowed)
    }
}
