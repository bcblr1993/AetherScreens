import XCTest
@testable import AetherScreensCore

final class FileTransferHistoryStoreTests: XCTestCase {
    func testPresetLocationsContainStandardMacDirectories() {
        let presets = FileTransferPresetLocation.standardPresets
        let paths = presets.map(\.path)
        XCTAssertTrue(paths.contains("~/Desktop"))
        XCTAssertTrue(paths.contains("~/Downloads"))
        XCTAssertTrue(paths.contains("~/Documents"))
        XCTAssertTrue(paths.contains("~"))
        XCTAssertTrue(paths.contains("/Applications"))

        for preset in presets {
            XCTAssertFalse(preset.titleKey.isEmpty)
            XCTAssertFalse(preset.systemIcon.isEmpty)
            XCTAssertFalse(preset.path.isEmpty)
        }
    }

    func testRecentUploadDestinationsDeduplicateAndLimitCount() throws {
        let suite = "test.aetherscreens.transfer-history.upload.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = FileTransferHistoryStore(userDefaults: defaults, maxHistoryItems: 3)
        XCTAssertTrue(store.recentUploadDestinations.isEmpty)

        store.recordUploadDestination("~/Desktop")
        store.recordUploadDestination("~/Downloads")
        store.recordUploadDestination("~/Documents")
        XCTAssertEqual(store.recentUploadDestinations, ["~/Documents", "~/Downloads", "~/Desktop"])

        // Re-adding ~/Desktop should bring it to the front without duplicates
        store.recordUploadDestination("~/Desktop")
        XCTAssertEqual(store.recentUploadDestinations, ["~/Desktop", "~/Documents", "~/Downloads"])

        // Adding a 4th item should evict the oldest (~/Downloads) because max is 3
        store.recordUploadDestination("/Users/Shared")
        XCTAssertEqual(store.recentUploadDestinations, ["/Users/Shared", "~/Desktop", "~/Documents"])
    }

    func testRecentDownloadPathsDeduplicateAndLimitCount() throws {
        let suite = "test.aetherscreens.transfer-history.download.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = FileTransferHistoryStore(userDefaults: defaults, maxHistoryItems: 3)
        XCTAssertTrue(store.recentDownloadPaths.isEmpty)

        store.recordDownloadPath("~/Desktop/photo.png")
        store.recordDownloadPath("~/Downloads/archive.zip")
        XCTAssertEqual(store.recentDownloadPaths, ["~/Downloads/archive.zip", "~/Desktop/photo.png"])

        // Re-adding ~/Desktop/photo.png should move to front
        store.recordDownloadPath("~/Desktop/photo.png")
        XCTAssertEqual(store.recentDownloadPaths, ["~/Desktop/photo.png", "~/Downloads/archive.zip"])

        store.clearRecentDownloads()
        XCTAssertTrue(store.recentDownloadPaths.isEmpty)
    }

    func testCombiningPresetLocationWithFilename() {
        XCTAssertEqual(
            FileTransferHistoryStore.combine(presetPath: "~/Desktop", filename: "file.txt"),
            "~/Desktop/file.txt"
        )
        XCTAssertEqual(
            FileTransferHistoryStore.combine(presetPath: "~/", filename: "file.txt"),
            "~/file.txt"
        )
        XCTAssertEqual(
            FileTransferHistoryStore.combine(presetPath: "~", filename: "file.txt"),
            "~/file.txt"
        )
        XCTAssertEqual(
            FileTransferHistoryStore.combine(presetPath: "/Applications", filename: "App.app"),
            "/Applications/App.app"
        )
        XCTAssertEqual(
            FileTransferHistoryStore.combine(presetPath: "~/Downloads", filename: "   trimmed.pdf  "),
            "~/Downloads/trimmed.pdf"
        )
    }

    func testIgnoresEmptyOrWhitespaceEntries() throws {
        let suite = "test.aetherscreens.transfer-history.empty.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = FileTransferHistoryStore(userDefaults: defaults)
        store.recordUploadDestination("   ")
        store.recordUploadDestination("")
        XCTAssertTrue(store.recentUploadDestinations.isEmpty)

        store.recordDownloadPath("   ")
        XCTAssertTrue(store.recentDownloadPaths.isEmpty)
    }

    @MainActor
    func testSessionViewModelFileUploadAndDownloadRecordsHistory() throws {
        let store = FileTransferHistoryStore.shared
        store.clearRecentUploads()
        store.clearRecentDownloads()
        defer {
            store.clearRecentUploads()
            store.clearRecentDownloads()
        }

        let device = RemoteDevice(name: "Test Mac", host: "127.0.0.1")
        let vm = SessionViewModel(device: device, password: nil)

        // When invalid path is passed, nothing is recorded
        vm.beginFileDownload(remotePath: "invalid-relative-path", destination: FileManager.default.temporaryDirectory) {}
        XCTAssertTrue(store.recentDownloadPaths.isEmpty)

        // Valid path formats (~/ or /) are recorded
        vm.beginFileDownload(remotePath: "~/Downloads/test.png", destination: FileManager.default.temporaryDirectory) {}
        XCTAssertEqual(store.recentDownloadPaths, ["~/Downloads/test.png"])

        // Upload invalid path
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        vm.beginFileUpload(url: tempFile, destination: "invalid-dest") {}
        XCTAssertTrue(store.recentUploadDestinations.isEmpty)

        // Valid upload destination
        vm.beginFileUpload(url: tempFile, destination: "~/Desktop") {}
        XCTAssertEqual(store.recentUploadDestinations, ["~/Desktop"])
    }
}
