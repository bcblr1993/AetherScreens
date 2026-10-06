import Foundation
import XCTest
import AetherScreensWidgetSupport
@testable import AetherScreensCore

final class WidgetProjectionTests: XCTestCase {
    @MainActor
    func testConstructionAndFreshReadDoNotOptInOrWrite() {
        let bytes = WidgetBytes()
        var writes = 0, reloads = 0
        let store = WidgetCatalogStore(readData: { bytes.get() }, writeData: { _ in writes += 1 },
                                       reloadTimelines: { reloads += 1 })
        XCTAssertTrue(store.catalog.entries.isEmpty)
        XCTAssertTrue(store.freshLaunchCatalog().entries.isEmpty)
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(reloads, 0)
    }

    @MainActor
    func testExplicitOptInPublishesOnlyOpaqueIDAndNormalizedAlias() throws {
        let bytes = WidgetBytes()
        var reloads = 0
        let store = WidgetCatalogStore(readData: { bytes.get() }, writeData: { bytes.set($0) },
                                       reloadTimelines: { reloads += 1 })
        let id = UUID()
        try store.setAlias("  Cafe\u{0301}  ", for: id)
        let data = try XCTUnwrap(bytes.get())
        let value = try XCTUnwrap(WidgetCatalog.decode(data))
        XCTAssertEqual(value.entries, [.init(id: id, alias: "Café")])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "entries"])
        let entry = try XCTUnwrap((object["entries"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(entry.keys), ["id", "alias"])
        XCTAssertEqual(reloads, 1)
        try store.setAlias("Café", for: id)
        XCTAssertEqual(reloads, 1)
    }

    @MainActor
    func testFailedContainerWriteCannotBecomeEnabledOrReloadWidget() throws {
        let bytes = WidgetBytes()
        var reloads = 0
        let store = WidgetCatalogStore(readData: { bytes.get() }, writeData: { _ in
            throw CocoaError(.fileWriteNoPermission)
        }, reloadTimelines: { reloads += 1 })
        XCTAssertThrowsError(try store.setAlias("Fixture", for: UUID())) {
            XCTAssertEqual($0 as? WidgetCatalogStore.Failure, .unavailable)
        }
        XCTAssertTrue(store.catalog.entries.isEmpty)
        XCTAssertTrue(store.freshLaunchCatalog().entries.isEmpty)
        XCTAssertNil(bytes.get())
        XCTAssertEqual(reloads, 0)
    }

    @MainActor
    func testMalformedProjectionIsNotOverwrittenByEditRemovalOrPrune() {
        let bytes = WidgetBytes(Data("{\"schemaVersion\":1,\"entries\":[],\"password\":\"fixed-fixture\"}".utf8))
        let original = bytes.get()
        var writes = 0
        let store = WidgetCatalogStore(readData: { bytes.get() }, writeData: { _ in writes += 1 })
        let id = UUID()
        XCTAssertThrowsError(try store.setAlias("Fixture", for: id))
        XCTAssertThrowsError(try store.remove(id: id))
        XCTAssertThrowsError(try store.prune(availableIDs: []))
        XCTAssertTrue(store.freshLaunchCatalog().entries.isEmpty)
        XCTAssertEqual(bytes.get(), original)
        XCTAssertEqual(writes, 0)
    }

    @MainActor
    func testAliasValidationNeverWritesOrReloads() throws {
        let bytes = WidgetBytes()
        var writes = 0, reloads = 0
        let store = WidgetCatalogStore(readData: { bytes.get() }, writeData: { _ in writes += 1 },
                                       reloadTimelines: { reloads += 1 })
        try store.validateAlias("Fixture", for: UUID())
        XCTAssertThrowsError(try store.validateAlias(" \n ", for: UUID()))
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(reloads, 0)
    }

    @MainActor
    func testRemovalReadsCurrentProjectionAndRetainsOtherProcessEdit() throws {
        let a = UUID(), b = UUID()
        let bytes = WidgetBytes(try JSONEncoder().encode(WidgetCatalog(entries: [.init(id: a, alias: "A")])))
        let store = WidgetCatalogStore(readData: { bytes.get() }, writeData: { bytes.set($0) })
        bytes.set(try JSONEncoder().encode(WidgetCatalog(entries: [.init(id: a, alias: "A"), .init(id: b, alias: "B")])))
        try store.remove(id: a)
        XCTAssertEqual(WidgetCatalog.decode(bytes.get())?.entries, [.init(id: b, alias: "B")])
        XCTAssertEqual(store.catalog.entries, [.init(id: b, alias: "B")])
    }

    @MainActor
    func testWidgetOnlyOptInDoesNotDependOnShortcutCatalog() throws {
        let id = UUID()
        let bytes = WidgetBytes(try JSONEncoder().encode(WidgetCatalog(entries: [.init(id: id, alias: "Fixture")])))
        let store = WidgetCatalogStore(readData: { bytes.get() }, writeData: { bytes.set($0) })
        let widgetQueue = ShortcutLaunchQueue(now: { 10 })
        let shortcutQueue = ShortcutLaunchQueue(now: { 10 })
        XCTAssertThrowsError(try shortcutQueue.enqueue(deviceID: id, catalog: ShortcutCatalog()))
        try widgetQueue.enqueue(deviceID: id, catalog: store.freshLaunchCatalog())
        XCTAssertNil(widgetQueue.takeNext(isActive: false, isReady: true,
            catalog: store.freshLaunchCatalog(), availableIDs: [id]))
        XCTAssertEqual(widgetQueue.takeNext(isActive: true, isReady: true,
            catalog: store.freshLaunchCatalog(), availableIDs: [id])?.deviceID, id)
        XCTAssertNil(widgetQueue.takeNext(isActive: true, isReady: true,
            catalog: store.freshLaunchCatalog(), availableIDs: [id]))
    }

    @MainActor
    func testRevokedWidgetCannotClaimEvenIfShortcutRemainsEnabled() throws {
        let id = UUID()
        let bytes = WidgetBytes(try JSONEncoder().encode(WidgetCatalog(entries: [.init(id: id, alias: "Fixture")])))
        let store = WidgetCatalogStore(readData: { bytes.get() }, writeData: { bytes.set($0) })
        let widgets = ShortcutLaunchQueue(now: { 10 })
        let shortcuts = ShortcutLaunchQueue(now: { 10 })
        let shortcutCatalog = ShortcutCatalog(entries: [.init(id: id, alias: "Fixture")])
        try widgets.enqueue(deviceID: id, catalog: store.freshLaunchCatalog())
        try shortcuts.enqueue(deviceID: id, catalog: shortcutCatalog)
        try store.remove(id: id)
        XCTAssertNil(widgets.takeNext(isActive: true, isReady: true,
            catalog: store.freshLaunchCatalog(), availableIDs: [id]))
        XCTAssertNotNil(shortcuts.takeNext(isActive: true, isReady: true,
            catalog: shortcutCatalog, availableIDs: [id]))
    }

    @MainActor
    func testWidgetClaimWaitsForLibraryAndDropsDeletedSavedRecord() throws {
        let id = UUID()
        let catalog = ShortcutCatalog(entries: [.init(id: id, alias: "Fixture")])
        let queue = ShortcutLaunchQueue(now: { 10 })
        try queue.enqueue(deviceID: id, catalog: catalog)
        XCTAssertNil(queue.takeNext(isActive: true, isReady: false, catalog: catalog, availableIDs: [id]))
        XCTAssertNil(queue.takeNext(isActive: true, isReady: true, catalog: catalog, availableIDs: []))
        XCTAssertNil(queue.takeNext(isActive: true, isReady: true, catalog: catalog, availableIDs: [id]))
    }

    @MainActor
    func testUnverifiedLibraryDefersWidgetWithoutDroppingItUntilRepair() throws {
        let id = UUID()
        let catalog = ShortcutCatalog(entries: [.init(id: id, alias: "Fixture")])
        let queue = ShortcutLaunchQueue(now: { 10 })
        try queue.enqueue(deviceID: id, catalog: catalog)
        XCTAssertNil(queue.takeNextWidget(isActive: true, isReady: true,
            catalog: catalog, verifiedAvailableIDs: nil))
        XCTAssertEqual(queue.takeNextWidget(isActive: true, isReady: true,
            catalog: catalog, verifiedAvailableIDs: [id])?.deviceID, id)
        XCTAssertNil(queue.takeNextWidget(isActive: true, isReady: true,
            catalog: catalog, verifiedAvailableIDs: [id]))
    }

    @MainActor
    func testUnavailableExistingProjectionCannotReportSuccessfulRevocation() throws {
        let id = UUID()
        let original = try JSONEncoder().encode(WidgetCatalog(entries: [.init(id: id, alias: "Fixture")]))
        let bytes = WidgetBytes(original)
        var unavailable = false, writes = 0, reloads = 0
        let store = WidgetCatalogStore(readData: { bytes.get() }, writeData: { _ in writes += 1 },
            reloadTimelines: { reloads += 1 }, readForEditing: {
                if unavailable { throw CocoaError(.fileReadNoPermission) }
                return bytes.get()
            })
        unavailable = true
        XCTAssertThrowsError(try store.remove(id: id)) {
            XCTAssertEqual($0 as? WidgetCatalogStore.Failure, .unavailable)
        }
        XCTAssertThrowsError(try store.prune(availableIDs: []))
        XCTAssertEqual(store.catalog.entries, [.init(id: id, alias: "Fixture")])
        XCTAssertEqual(bytes.get(), original)
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(reloads, 0)
        unavailable = false
        XCTAssertEqual(store.freshLaunchCatalog().entries.map(\.id), [id])
    }
}

private final class WidgetBytes: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: Data?
    init(_ bytes: Data? = nil) { self.bytes = bytes }
    func get() -> Data? { lock.lock(); defer { lock.unlock() }; return bytes }
    func set(_ bytes: Data?) { lock.lock(); defer { lock.unlock() }; self.bytes = bytes }
}
