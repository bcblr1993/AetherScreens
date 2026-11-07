import XCTest
@testable import AetherScreensCore

final class Phase11QuickSnippetsManagerTests: XCTestCase {

    @MainActor
    func testQuickSnippetUpdateReorderAndResetToDefaults() throws {
        let suiteName = "com.aetherscreens.tests.phase11.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = QuickSnippetStore(defaults: defaults, seedDefaultsIfEmpty: false)
        let s1 = QuickSnippet(title: "First", content: "echo 1", appendReturn: true)
        let s2 = QuickSnippet(title: "Second", content: "echo 2", appendReturn: false)
        let s3 = QuickSnippet(title: "Third", content: "echo 3", appendReturn: true)

        store.add(s1)
        store.add(s2)
        store.add(s3)
        XCTAssertEqual(store.snippets.map(\.title), ["First", "Second", "Third"])

        // 1. Update s2
        let updatedS2 = QuickSnippet(id: s2.id, title: "Second Updated", content: "echo 22", appendReturn: true)
        store.update(updatedS2)
        XCTAssertEqual(store.snippets[1].title, "Second Updated")
        XCTAssertEqual(store.snippets[1].content, "echo 22")
        XCTAssertTrue(store.snippets[1].appendReturn)

        // 2. Move "Third" (index 2) to the front (index 0)
        store.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(store.snippets.map(\.title), ["Third", "First", "Second Updated"])

        // Verify persistence
        let reloaded = QuickSnippetStore(defaults: defaults, seedDefaultsIfEmpty: false)
        XCTAssertEqual(reloaded.snippets.map(\.title), ["Third", "First", "Second Updated"])

        // 3. Reset to defaults
        reloaded.resetToDefaults()
        XCTAssertEqual(reloaded.snippets.count, 3)
        XCTAssertEqual(reloaded.snippets.first?.title, "System Uptime")
    }
}
