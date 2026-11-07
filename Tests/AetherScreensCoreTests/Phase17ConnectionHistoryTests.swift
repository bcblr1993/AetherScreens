import XCTest
@testable import AetherScreensCore

final class Phase17ConnectionHistoryTests: XCTestCase {

    @MainActor
    func testConnectionHistoryRecordingDurationFilteringAndMaxCapacity() throws {
        let suiteName = "Phase17Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ConnectionHistoryStore(defaults: defaults, maxEntries: 5)
        let dev1 = UUID()
        let dev2 = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        // 1. Record a session start and completion
        let entryID = store.recordSessionStart(
            deviceID: dev1,
            deviceName: "Studio Mac",
            host: "100.80.1.10",
            port: 5900,
            remoteProtocol: .rfb,
            startedAt: start
        )
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertNil(store.entries.first?.endedAt)

        store.recordSessionEnd(
            id: entryID,
            endedAt: start.addingTimeInterval(125),
            outcome: .completed
        )
        let completed = try XCTUnwrap(store.entries.first)
        XCTAssertEqual(completed.durationSeconds, 125)
        XCTAssertEqual(completed.outcome, .completed)

        // 2. Record 5 more entries for dev2 to verify maxEntries ring-buffer bounding (maxEntries = 5)
        for i in 1...5 {
            _ = store.recordSessionStart(
                deviceID: dev2,
                deviceName: "Win Workstation \(i)",
                host: "10.0.0.\(i)",
                port: 3389,
                remoteProtocol: .rdp,
                startedAt: start.addingTimeInterval(Double(i * 200))
            )
        }
        XCTAssertEqual(store.entries.count, 5)
        // Most recent entry is first
        XCTAssertEqual(store.entries.first?.deviceName, "Win Workstation 5")
        // Oldest entry (dev1) was evicted when 6th entry arrived
        XCTAssertTrue(store.entries(for: dev1).isEmpty)
        XCTAssertEqual(store.entries(for: dev2).count, 5)

        // 3. Reload from UserDefaults and verify persistence
        let reloaded = ConnectionHistoryStore(defaults: defaults, maxEntries: 5)
        XCTAssertEqual(reloaded.entries.count, 5)
        XCTAssertEqual(reloaded.entries.first?.deviceName, "Win Workstation 5")

        // 4. Clear history
        reloaded.clearAll()
        XCTAssertTrue(reloaded.entries.isEmpty)
    }
}
