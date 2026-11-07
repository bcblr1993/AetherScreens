import XCTest
import CoreGraphics
@testable import AetherScreensCore

final class Phase24UIResponsivenessAndStorageAuditFixesTests: XCTestCase {

    func testWakeOnLANServiceRejectsPortZeroWithoutCrash() {
        let portZeroExpectation = expectation(description: "port 0 completion")
        WakeOnLANService.wakeDevice(macAddress: "AA:BB:CC:DD:EE:FF", port: 0) { success in
            XCTAssertFalse(success, "Port 0 must safely fail instead of trapping on NWEndpoint.Port(rawValue: 0)!")
            portZeroExpectation.fulfill()
        }

        let invalidMACExpectation = expectation(description: "invalid MAC completion")
        WakeOnLANService.wakeDevice(macAddress: "not-a-mac", port: 9) { success in
            XCTAssertFalse(success)
            invalidMACExpectation.fulfill()
        }

        wait(for: [portZeroExpectation, invalidMACExpectation], timeout: 2.0)
    }

    func testTailscaleClientPercentEncodesTailnetInEndpointURL() throws {
        let client = TailscaleClient(apiKey: "tskey-test", tailnet: "team space/ops#1")
        let url = try XCTUnwrap(client.devicesEndpointURL())
        XCTAssertEqual(
            url.absoluteString,
            "https://api.tailscale.com/api/v2/tailnet/team%20space%2Fops%231/devices"
        )
    }

    @MainActor
    func testDeviceStoreBatchUpdateAndDeviceListViewModelTagCacheConsistency() throws {
        let suiteName = "AetherScreensTests.Phase24.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DeviceStore(userDefaults: defaults)
        let d1 = RemoteDevice(name: "Alpha", host: "10.0.0.1", tags: ["Prod", "Mac"])
        let d2 = RemoteDevice(name: "Beta", host: "10.0.0.2", tags: ["Prod"])
        let d3 = RemoteDevice(name: "Gamma", host: "10.0.0.3", tags: ["Staging"])
        _ = store.addDevice(d1)
        _ = store.addDevice(d2)
        _ = store.addDevice(d3)

        let vm = DeviceListViewModel(store: store, userDefaults: defaults)
        XCTAssertEqual(vm.allTags, ["Mac", "Prod", "Staging"])
        XCTAssertEqual(vm.tagCounts["Prod"], 2)
        XCTAssertEqual(vm.tagCounts["Mac"], 1)
        XCTAssertEqual(vm.tagCounts["Staging"], 1)

        // Batch assign a new tag across all 3 devices
        let assigned = vm.assignTag("Core", toDeviceIDs: [d1.id, d2.id, d3.id])
        XCTAssertEqual(assigned, 3)
        XCTAssertEqual(vm.allTags, ["Core", "Mac", "Prod", "Staging"])
        XCTAssertEqual(vm.tagCounts["Core"], 3)

        // Batch remove tag
        let removed = vm.removeTag("Prod", fromDeviceIDs: [d1.id, d2.id])
        XCTAssertEqual(removed, 2)
        XCTAssertEqual(vm.allTags, ["Core", "Mac", "Staging"])
        XCTAssertNil(vm.tagCounts["Prod"])
    }

    func testThumbnailStoreAllowsSavingNewThumbnailAfterDeviceReAdded() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("AetherScreens_Phase24Thumb_\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tempDir) }

        let store = ThumbnailStore(cacheDirectory: tempDir)
        let deviceID = UUID()

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = try XCTUnwrap(
            CGContext(
                data: nil,
                width: 16,
                height: 16,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        let image = try XCTUnwrap(ctx.makeImage())

        store.saveThumbnail(image, for: deviceID)
        XCTAssertNotNil(store.getThumbnail(for: deviceID))

        // Removing the device clears the thumbnail and marks it removed
        store.removeThumbnail(for: deviceID)
        XCTAssertNil(store.getThumbnail(for: deviceID))

        // Re-allowing thumbnails when a device with that UUID is re-added / re-imported allows new saves
        store.allowThumbnails(for: deviceID)
        store.saveThumbnail(image, for: deviceID)
        XCTAssertNotNil(store.getThumbnail(for: deviceID))
    }

    @MainActor
    func testConnectionHistoryStoreReconcilesStaleActiveEntriesOnLoadAndQuickSnippetStoreBoundsLength() throws {
        let suiteName = "AetherScreensTests.Phase24History.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // 1. Create an active entry in first store instance (simulating previous app run before force-quit)
        let deviceID = UUID()
        let start = Date(timeIntervalSinceNow: -120)
        do {
            let store1 = ConnectionHistoryStore(defaults: defaults)
            _ = store1.recordSessionStart(
                deviceID: deviceID,
                deviceName: "Studio Mac",
                host: "10.0.0.9",
                port: 5900,
                remoteProtocol: .rfb,
                startedAt: start
            )
            XCTAssertEqual(store1.entries.first?.outcome, .active)
        }

        // 2. Initializing a new ConnectionHistoryStore on next launch must reconcile stale `.active` entries to `.completed`
        let store2 = ConnectionHistoryStore(defaults: defaults)
        let reconciled = try XCTUnwrap(store2.entries.first)
        XCTAssertEqual(reconciled.outcome, .completed)
        XCTAssertNotNil(reconciled.endedAt)

        // 3. QuickSnippetStore bounds title and content lengths
        let snippetStore = QuickSnippetStore(defaults: defaults, seedDefaultsIfEmpty: false)
        let hugeTitle = String(repeating: "T", count: 500)
        let hugeContent = String(repeating: "C", count: 40_000)
        snippetStore.add(QuickSnippet(title: hugeTitle, content: hugeContent, appendReturn: true))

        let saved = try XCTUnwrap(snippetStore.snippets.first)
        XCTAssertEqual(saved.title.count, QuickSnippetStore.maxTitleLength)
        XCTAssertEqual(saved.content.count, QuickSnippetStore.maxContentLength)
    }
}
