import XCTest
@testable import AetherScreensCore

@MainActor
final class DisplayQualityStoreTests: XCTestCase {
    func testAutomaticPreferenceIsIndependentAndTemporarySessionsNeverPersistIt() throws {
        let suite = "AutomaticQualityQA-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DisplayQualityStore(defaults: defaults)
        let device = RemoteDevice(name: "Quality QA", host: "127.0.0.1")
        XCTAssertFalse(store.loadAutomatic(for: device.id))
        store.save(.rgb565, for: device.id)
        let session = SessionViewModel(device: device, password: nil, displayQualityStore: store)
        session.selectAutomaticDisplayQuality(true)
        XCTAssertTrue(store.loadAutomatic(for: device.id))
        XCTAssertEqual(store.load(for: device.id), .rgb565)
        XCTAssertEqual(session.client.state, .disconnected, "Changing compression must not initiate a connection")
        session.setForegroundSession(false)
        session.selectAutomaticDisplayQuality(false)
        XCTAssertTrue(session.automaticDisplayQuality)
        let restored = SessionViewModel(device: device, password: nil, displayQualityStore: store)
        XCTAssertTrue(restored.automaticDisplayQuality)
        let temporary = SessionViewModel(device: device, password: nil, isTemporary: true, displayQualityStore: store)
        XCTAssertFalse(temporary.automaticDisplayQuality)
        temporary.selectAutomaticDisplayQuality(true)
        temporary.selectAutomaticDisplayQuality(false)
        XCTAssertTrue(store.loadAutomatic(for: device.id))
        store.remove(for: device.id)
        XCTAssertFalse(store.loadAutomatic(for: device.id))
        XCTAssertEqual(store.load(for: device.id), .fullColor)
    }

    func testSavedSessionLoadsPreferenceButTemporarySessionKeepsFullColor() throws {
        let suite = "DisplayQualityQA-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DisplayQualityStore(defaults: defaults)
        let device = RemoteDevice(name: "Quality QA", host: "127.0.0.1")
        store.save(.rgb565, for: device.id)
        let saved = SessionViewModel(device: device, password: nil, displayQualityStore: store)
        XCTAssertEqual(saved.displayColorDepth, .rgb565)
        XCTAssertEqual(saved.client.colorDepth, .rgb565)
        let temporary = SessionViewModel(device: device, password: nil, isTemporary: true, displayQualityStore: store)
        XCTAssertEqual(temporary.client.colorDepth, .fullColor)
        saved.setForegroundSession(false)
        saved.selectDisplayColorDepth(.fullColor)
        XCTAssertEqual(saved.displayColorDepth, .rgb565)
        XCTAssertEqual(saved.client.state, .disconnected)
        XCTAssertEqual(store.load(for: device.id), .rgb565)
    }

    func testSeparateComputerPreferencesSurviveStoreRecreation() throws {
        let suite = "DisplayQualityQA-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = UUID(), second = UUID()
        let store = DisplayQualityStore(defaults: defaults)
        XCTAssertEqual(store.load(for: first), .fullColor)
        store.save(.rgb565, for: first)
        let restored = DisplayQualityStore(defaults: defaults)
        XCTAssertEqual(restored.load(for: first), .rgb565)
        XCTAssertEqual(restored.load(for: second), .fullColor)
        restored.save(.fullColor, for: first)
        XCTAssertEqual(store.load(for: first), .fullColor)
    }

    func testUnknownStoredPrecisionFallsBackToFullColor() throws {
        let suite = "DisplayQualityQA-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let device = UUID()
        defaults.set("future-format", forKey: "aetherscreens.display-color-depth." + device.uuidString)
        XCTAssertEqual(DisplayQualityStore(defaults: defaults).load(for: device), .fullColor)
    }
}
