import XCTest
@testable import AetherScreensCore
#if os(macOS)
import AppKit
#endif

final class Phase25HIGLocalizationAndInputPolishTests: XCTestCase {

    func testAllQuickSnippetAndLibraryNoticeKeysExistInEnglishAndSimplifiedChinese() {
        let requiredKeys = [
            "Edit Quick Snippet",
            "Snippet Title (e.g. Restart Nginx)",
            "Command or Text Content",
            "Append Return (⏎) After Sending",
            "No saved snippets yet",
            "Reset Defaults",
            "Could not read ~/.ssh/config",
            "Wake-on-LAN Magic Packet sent to %@",
            "Failed to send Wake-on-LAN packet. Check MAC format.",
            "Could not remove the SSH password from Keychain. The computer was kept.",
            "No matching computers",
            "Reset Filters",
            "Send",
            "Edit"
        ]

        for key in requiredKeys {
            let enValue = AppLocalization.string(key, language: .english)
            let zhValue = AppLocalization.string(key, language: .simplifiedChinese)
            XCTAssertFalse(enValue.isEmpty, "Missing English localization for key: \(key)")
            XCTAssertFalse(zhValue.isEmpty, "Missing Simplified Chinese localization for key: \(key)")
            XCTAssertNotEqual(
                zhValue,
                key,
                "Simplified Chinese translation should not fall back to raw English key for: \(key)"
            )
        }
    }

    @MainActor
    func testDeviceListViewModelHasActiveFiltersAndResetFilters() throws {
        let suiteName = "AetherScreensTests.Phase25.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DeviceStore(userDefaults: defaults)
        _ = store.addDevice(RemoteDevice(name: "Office Mac", host: "10.0.0.10", isOnline: false, tags: ["Work"]))
        let vm = DeviceListViewModel(store: store, userDefaults: defaults)

        XCTAssertFalse(vm.hasActiveFilters)
        XCTAssertEqual(vm.filteredDevices.count, 1)

        // Filtering by onlineOnly hides the offline computer and marks hasActiveFilters = true
        vm.smartFilter = .onlineOnly
        XCTAssertTrue(vm.hasActiveFilters)
        XCTAssertTrue(vm.filteredDevices.count == 0)

        // Filtering by tag and search text
        vm.selectedTag = "NonExistent"
        vm.searchText = "missing"
        XCTAssertTrue(vm.hasActiveFilters)

        // Resetting filters restores all computers immediately
        vm.resetFilters()
        XCTAssertFalse(vm.hasActiveFilters)
        XCTAssertEqual(vm.searchText, "")
        XCTAssertNil(vm.selectedTag)
        XCTAssertEqual(vm.smartFilter, .all)
        XCTAssertEqual(vm.filteredDevices.count, 1)
    }

    #if os(macOS)
    @MainActor
    func testMacNativeInputViewIMECandidateRectTracksPointerInsideBoundsAndFallsBackToMidpoint() {
        let view = MacNativeInputView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        // Without pointer tracking, IME candidate rect defaults to view center
        let defaultRect = view.candidateRectInViewBounds()
        XCTAssertEqual(defaultRect.origin.x, 400, accuracy: 0.5)
        XCTAssertEqual(defaultRect.origin.y, 300, accuracy: 0.5)

        // With an active pointer location in view coordinates, IME candidate rect anchors at pointer
        let pointerRect = view.candidateRectInViewBounds(preferredViewPoint: NSPoint(x: 220, y: 180))
        XCTAssertEqual(pointerRect.origin.x, 220, accuracy: 0.5)
        XCTAssertEqual(pointerRect.origin.y, 180, accuracy: 0.5)
        XCTAssertEqual(pointerRect.height, 20, accuracy: 0.5)

        // Out-of-bounds points clamp safely inside the view bounds
        let clampedRect = view.candidateRectInViewBounds(preferredViewPoint: NSPoint(x: 950, y: -40))
        XCTAssertLessThanOrEqual(clampedRect.maxX, 800)
        XCTAssertGreaterThanOrEqual(clampedRect.minY, 0)
    }
    #endif
}
