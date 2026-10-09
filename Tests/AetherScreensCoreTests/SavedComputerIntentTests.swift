import XCTest
@testable import AetherScreensCore

@MainActor
final class SavedComputerIntentTests: XCTestCase {
    func testColdStartInboxPreservesOrderAndCoalescesPendingDuplicate() {
        let inbox = SavedComputerIntentInbox()
        let first = UUID(), second = UUID()
        inbox.enqueue(first); inbox.enqueue(second); inbox.enqueue(first)
        XCTAssertEqual(inbox.drain(), [first, second])
        XCTAssertTrue(inbox.drain().isEmpty)
        inbox.enqueue(first)
        XCTAssertEqual(inbox.drain(), [first])
    }

    func testQueryReloadsSavedComputersAndRejectsDeletedIdentifier() async throws {
        let suite = "SavedIntentQA-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = KeychainStore(serviceName: suite, legacyServiceName: nil)
        let store = DeviceStore(userDefaults: defaults, keychain: keychain)
        let first = RemoteDevice(name: "Desk", host: "one.invalid")
        let second = RemoteDevice(name: "Desk", host: "two.invalid")
        store.addDevice(first); store.addDevice(second)
        defer { store.deleteDevice(first); store.deleteDevice(second) }
        let query = SavedComputerQuery(store: store)
        let entities = try await query.entities(for: [second.id, first.id])
        XCTAssertEqual(entities.map(\.id), [second.id, first.id])
        XCTAssertEqual(entities.map(\.host), ["two.invalid", "one.invalid"])
        let suggestions = try await query.suggestedEntities()
        XCTAssertEqual(suggestions.count, 2)
        store.deleteDevice(first)
        let remaining = try await query.entities(for: [first.id, second.id])
        XCTAssertEqual(remaining.map(\.id), [second.id])
        let url = ConnectionLink.savedURL(for: second.id)
        XCTAssertNil(URLComponents(url: url, resolvingAgainstBaseURL: false)?.user)
        XCTAssertNil(URLComponents(url: url, resolvingAgainstBaseURL: false)?.password)
    }
}
