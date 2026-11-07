import XCTest
@testable import AetherScreensCore

final class Phase12MultiDisplayMemoryTests: XCTestCase {

    func testDisplaySelectionStorePersistenceAndMultiDisplayManagerRestore() throws {
        let suiteName = "com.aetherscreens.tests.phase12.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DisplaySelectionStore(defaults: defaults)
        let deviceID = UUID()

        // 1. Initially nil
        XCTAssertNil(store.load(for: deviceID))

        // 2. Bind manager1, configure 2x horizontal split and select Display 2
        let manager1 = MultiDisplayManager()
        manager1.bindDevicePreferences(deviceID: deviceID, store: store)
        manager1.updateFromFramebuffer(width: 3840, height: 1080)
        manager1.setVirtualSplitMode(.twoHorizontal)
        manager1.selectDisplay(id: 2)

        let saved = try XCTUnwrap(store.load(for: deviceID))
        XCTAssertEqual(saved.virtualSplitMode, .twoHorizontal)
        XCTAssertEqual(saved.selectedDisplayID, 2)

        // 3. New manager2 for the same deviceID restores both virtualSplitMode and selectedDisplayId upon framebuffer update
        let manager2 = MultiDisplayManager()
        manager2.bindDevicePreferences(deviceID: deviceID, store: store)
        manager2.updateFromFramebuffer(width: 3840, height: 1080)
        XCTAssertEqual(manager2.virtualSplitMode, .twoHorizontal)
        XCTAssertEqual(manager2.selectedDisplayId, 2)
        XCTAssertEqual(manager2.currentDisplay?.bounds, CGRect(x: 1920, y: 0, width: 1920, height: 1080))

        // 4. Removing preferences clears stored entry
        store.remove(for: deviceID)
        XCTAssertNil(store.load(for: deviceID))
    }
}
