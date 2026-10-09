import XCTest
import Security
@testable import AetherScreensCore

final class SSHCredentialStoreTests: XCTestCase {
    private final class Access: SSHKeychainAccess {
        var updateStatus: OSStatus = errSecItemNotFound
        var addStatus: OSStatus = errSecSuccess
        var readStatus: OSStatus = errSecItemNotFound
        var deleteStatus: OSStatus = errSecSuccess
        var value: Data?
        var added: [String: Any]?
        var queries: [[String: Any]] = []
        var deleteCount = 0
        var addCount = 0
        var accountsStatus: OSStatus = errSecItemNotFound
        var listedAccounts: [String]?
        func accounts(_ query: [String: Any]) -> (OSStatus, [String]?) {
            queries.append(query); return (accountsStatus, listedAccounts)
        }
        func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
            queries.append(query)
            if updateStatus == errSecSuccess { value = attributes[kSecValueData as String] as? Data }
            return updateStatus
        }
        func add(_ attributes: [String: Any]) -> OSStatus {
            addCount += 1; added = attributes
            if addStatus == errSecSuccess { value = attributes[kSecValueData as String] as? Data }
            return addStatus
        }
        func copy(_ query: [String: Any]) -> (OSStatus, Data?) { queries.append(query); return (readStatus, value) }
        func delete(_ query: [String: Any]) -> OSStatus { queries.append(query); deleteCount += 1; return deleteStatus }
    }

    func testDeniedWriteDoesNotDeleteExistingSecretOrCacheReplacement() throws {
        let access = Access(), old = Data("old QA value".utf8)
        access.value = old; access.updateStatus = errSecInteractionNotAllowed; access.readStatus = errSecSuccess
        let store = SSHCredentialStore(service: "qa-only", access: access), id = UUID()
        XCTAssertThrowsError(try store.save(Data("replacement QA value".utf8), kind: .password, reference: id)) {
            XCTAssertEqual(($0 as? SSHCredentialStore.Failure)?.status, errSecInteractionNotAllowed)
        }
        XCTAssertEqual(try store.load(kind: .password, reference: id), old)
        XCTAssertEqual(access.deleteCount, 0)
        XCTAssertEqual(access.addCount, 0)
        access.readStatus = errSecInteractionNotAllowed
        XCTAssertThrowsError(try store.load(kind: .password, reference: id), "No in-memory fallback after a denied Keychain read")
    }

    func testAddFailureIsNotReportedAsSavedAndKindsAreIsolated() throws {
        let access = Access(), id = UUID()
        access.addStatus = errSecMissingEntitlement
        let store = SSHCredentialStore(service: "qa-only", access: access)
        XCTAssertThrowsError(try store.save(Data([1]), kind: .privateKey, reference: id))
        XCTAssertNil(try store.load(kind: .privateKey, reference: id))
        XCTAssertEqual(access.added?[kSecAttrAccessible as String] as? String,
                       kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        XCTAssertEqual(access.added?[kSecAttrSynchronizable as String] as? Bool, false)
        _ = try store.load(kind: .password, reference: id)
        _ = try store.load(kind: .passphrase, reference: id)
        XCTAssertEqual(Set(access.queries.compactMap { $0[kSecAttrAccount as String] as? String }).count, 3)
        XCTAssertEqual(access.deleteCount, 0)
    }

    func testExistingItemUpdatesWithoutDeleteAndReadErrorsRemainErrors() throws {
        let access = Access(), id = UUID(), value = Data([1, 2, 3])
        let store = SSHCredentialStore(service: "qa-only", access: access)
        access.updateStatus = errSecSuccess; access.readStatus = errSecSuccess
        try store.save(value, kind: .privateKey, reference: id)
        XCTAssertEqual(try store.load(kind: .privateKey, reference: id), value)
        XCTAssertEqual(access.addCount, 0); XCTAssertEqual(access.deleteCount, 0)
        access.value = nil
        XCTAssertThrowsError(try store.load(kind: .privateKey, reference: id))
        access.deleteStatus = errSecInteractionNotAllowed
        XCTAssertThrowsError(try store.remove(kind: .privateKey, reference: id))
        access.deleteStatus = errSecItemNotFound
        XCTAssertNoThrow(try store.remove(kind: .privateKey, reference: id))
    }

    func testActualKeychainSaveUpdateReadDelete() throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_SSH_KEYCHAIN_QA"] == "1" else {
            throw XCTSkip("Requires explicit system Keychain QA")
        }
        let store = SSHCredentialStore(service: "test.aetherscreens.ssh." + UUID().uuidString), id = UUID()
        defer { for kind in [SSHCredentialStore.Kind.password, .privateKey, .passphrase] { try? store.remove(kind: kind, reference: id) } }
        for kind in [SSHCredentialStore.Kind.password, .privateKey, .passphrase] {
            XCTAssertEqual(try store.references(kind: kind), [])
            XCTAssertNil(try store.load(kind: kind, reference: id))
            try store.save(Data([1, 2, 3]), kind: kind, reference: id)
            XCTAssertEqual(try store.references(kind: kind), [id])
            XCTAssertEqual(try store.load(kind: kind, reference: id), Data([1, 2, 3]))
            try store.save(Data([4, 5, 6]), kind: kind, reference: id)
            XCTAssertEqual(try store.load(kind: kind, reference: id), Data([4, 5, 6]))
            try store.remove(kind: kind, reference: id)
            XCTAssertNil(try store.load(kind: kind, reference: id))
            XCTAssertEqual(try store.references(kind: kind), [])
        }
    }

    func testIdentityIndexFiltersKindsAndFailsClosedWithoutReadingSecretData() throws {
        let access = Access(), id = UUID()
        let store = SSHCredentialStore(service: "qa-only", access: access)
        XCTAssertEqual(try store.references(kind: .privateKey), [])
        access.accountsStatus = errSecSuccess
        access.listedAccounts = ["privateKey." + id.uuidString, "password." + UUID().uuidString,
                                 "privateKey." + id.uuidString]
        XCTAssertEqual(try store.references(kind: .privateKey), [id])
        XCTAssertNil(access.queries.last?[kSecReturnData as String])
        XCTAssertNil(access.queries.last?[kSecAttrAccount as String])
        XCTAssertEqual(access.queries.last?[kSecAttrService as String] as? String, "qa-only")
        access.accountsStatus = errSecInteractionNotAllowed
        XCTAssertThrowsError(try store.references(kind: .privateKey))
        access.accountsStatus = errSecSuccess; access.listedAccounts = ["privateKey.corrupt"]
        XCTAssertThrowsError(try store.references(kind: .privateKey))
    }
}
