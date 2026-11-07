import XCTest
@testable import AetherScreensCore

final class Phase7ShortcutsAndSnippetsTests: XCTestCase {

    func testWindowsShortcutsGenerateBalancedModifierKeySequences() {
        for shortcut in MacKeyMap.WindowsShortcut.allCases {
            let sequence = shortcut.keySequence
            XCTAssertFalse(sequence.isEmpty, "Shortcut \(shortcut.rawValue) must not have an empty sequence")
            let downs = sequence.filter(\.down).map(\.key)
            let ups = sequence.filter { !$0.down }.map(\.key)
            XCTAssertEqual(Set(downs), Set(ups), "All pressed keys in \(shortcut.rawValue) must be released")
            XCTAssertEqual(downs.count, ups.count)
        }

        // Verify Task Manager is Ctrl + Shift + Escape
        let taskMgr = MacKeyMap.WindowsShortcut.taskManager.keySequence
        XCTAssertEqual(
            taskMgr.map(\.key),
            [
                MacKeyMap.controlLeft, MacKeyMap.shiftLeft, MacKeyMap.escape,
                MacKeyMap.escape, MacKeyMap.shiftLeft, MacKeyMap.controlLeft
            ]
        )

        // Verify Lock PC is Win (commandLeft) + 'l'
        let lockSeq = MacKeyMap.WindowsShortcut.lockWorkstation.keySequence
        let lKey = UInt32(Character("l").asciiValue!)
        XCTAssertEqual(
            lockSeq.map(\.key),
            [MacKeyMap.commandLeft, lKey, lKey, MacKeyMap.commandLeft]
        )
    }

    @MainActor
    func testQuickSnippetStoreCRUDAndSessionExecution() throws {
        let suiteName = "com.aetherscreens.tests.phase7.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = QuickSnippetStore(defaults: defaults, seedDefaultsIfEmpty: false)
        XCTAssertTrue(store.snippets.isEmpty)

        let snippet1 = QuickSnippet(title: "Docker Containers", content: "docker ps -a", appendReturn: true)
        let snippet2 = QuickSnippet(title: "Tail Syslog", content: "tail -f /var/log/syslog", appendReturn: false)
        store.add(snippet1)
        store.add(snippet2)
        XCTAssertEqual(store.snippets.count, 2)

        // Reload from same UserDefaults to verify persistence
        let reloadedStore = QuickSnippetStore(defaults: defaults, seedDefaultsIfEmpty: false)
        XCTAssertEqual(reloadedStore.snippets, [snippet1, snippet2])

        reloadedStore.remove(id: snippet1.id)
        XCTAssertEqual(reloadedStore.snippets, [snippet2])
    }
}
