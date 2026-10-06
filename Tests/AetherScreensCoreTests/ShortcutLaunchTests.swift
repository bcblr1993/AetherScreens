import Foundation
import XCTest
@testable import AetherScreensCore

@MainActor
final class ShortcutLaunchTests: XCTestCase {
    func testAliasRequiresVisibleBaseWhenJoinersAreAllowed() {
        XCTAssertNil(ShortcutCatalog.normalizedAlias("\u{200C}"))
        XCTAssertNil(ShortcutCatalog.normalizedAlias("\u{200D}\u{200C}"))
        XCTAssertNil(ShortcutCatalog.normalizedAlias("\u{0301}"))
        XCTAssertEqual(ShortcutCatalog.normalizedAlias("电脑👩‍💻"), "电脑👩‍💻")
    }

    func testCatalogRoundTripPersistsOnlySchemaUUIDAndAlias() throws {
        let catalog = makeCatalog([1, 2])
        let data = try JSONEncoder().encode(catalog)
        try assertProjection(data, expectedIDs: [identifier(1), identifier(2)])
        let decoded = try XCTUnwrap(ShortcutCatalog.decode(data))
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.entries, catalog.entries)
    }

    func testCatalogDecodeRequiresExactRootAndEntryKeys() throws {
        let entry: [String: Any] = ["id": identifier(1).uuidString, "alias": "Slot 1"]
        let fixtures: [Any] = [
            ["entries": [entry]],
            ["schemaVersion": 1],
            ["schemaVersion": 1, "entries": [entry], "extra": "synthetic"],
            ["schemaVersion": 1, "entries": [["id": identifier(1).uuidString]]],
            ["schemaVersion": 1, "entries": [["alias": "Slot 1"]]],
            ["schemaVersion": 1, "entries": [["id": identifier(1).uuidString, "alias": "Slot 1", "extra": 0]]]
        ]
        for (index, fixture) in fixtures.enumerated() {
            XCTAssertNil(ShortcutCatalog.decode(try jsonData(fixture)), "Fixture \(index)")
        }
    }

    func testCatalogDecodeRejectsWrongSchemaAndValueTypes() throws {
        let entry: [String: Any] = ["id": identifier(1).uuidString, "alias": "Slot 1"]
        let fixtures: [Any] = [
            [],
            ["schemaVersion": 0, "entries": [entry]],
            ["schemaVersion": 2, "entries": [entry]],
            ["schemaVersion": "1", "entries": [entry]],
            ["schemaVersion": true, "entries": [entry]],
            ["schemaVersion": NSNull(), "entries": [entry]],
            ["schemaVersion": 1, "entries": entry],
            ["schemaVersion": 1, "entries": NSNull()],
            ["schemaVersion": 1, "entries": [NSNull()]],
            ["schemaVersion": 1, "entries": [["id": "invalid UUID", "alias": "Slot 1"]]],
            ["schemaVersion": 1, "entries": [["id": 1, "alias": "Slot 1"]]],
            ["schemaVersion": 1, "entries": [["id": NSNull(), "alias": "Slot 1"]]],
            ["schemaVersion": 1, "entries": [["id": identifier(1).uuidString, "alias": 1]]],
            ["schemaVersion": 1, "entries": [["id": identifier(1).uuidString, "alias": NSNull()]]]
        ]
        for (index, fixture) in fixtures.enumerated() {
            XCTAssertNil(ShortcutCatalog.decode(try jsonData(fixture)), "Fixture \(index)")
        }
    }

    func testCatalogDecodeRejectsDuplicateIdentifiersAndObjectKeys() throws {
        let id = identifier(1)
        let duplicated = ShortcutCatalog(entries: [
            .init(id: id, alias: "Slot 1"), .init(id: id, alias: "Slot 2")
        ])
        XCTAssertNil(ShortcutCatalog.decode(try JSONEncoder().encode(duplicated)))
        let fixtures = [
            "{\"schemaVersion\":1,\"schemaVersion\":1,\"entries\":[]}",
            "{\"schemaVersion\":1,\"sche\\u006daVersion\":1,\"entries\":[]}",
            "{\"schemaVersion\":1,\"entries\":[],\"entries\":[]}",
            "{\"schemaVersion\":1,\"entries\":[{\"id\":\"\(id.uuidString)\",\"alias\":\"Slot 1\",\"alias\":\"Slot 2\"}]}",
            "{\"schemaVersion\":1,\"entries\":[{\"id\":\"\(id.uuidString)\",\"id\":\"\(id.uuidString)\",\"alias\":\"Slot 1\"}]}"
        ]
        for (index, fixture) in fixtures.enumerated() {
            XCTAssertNil(ShortcutCatalog.decode(Data(fixture.utf8)), "Fixture \(index)")
        }
    }

    func testCatalogDecodeEnforcesDataByteBoundaryAndMalformedFailsClosed() throws {
        var boundary = try JSONEncoder().encode(ShortcutCatalog())
        boundary.append(Data(repeating: 0x20, count: 32_768 - boundary.count))
        XCTAssertEqual(boundary.count, 32_768)
        XCTAssertNotNil(ShortcutCatalog.decode(boundary))
        boundary.append(0x20)
        XCTAssertNil(ShortcutCatalog.decode(boundary))
        XCTAssertNil(ShortcutCatalog.decode(nil))
        XCTAssertNil(ShortcutCatalog.decode(Data()))
        for fixture in ["{", "null", "{\"schemaVersion\":1,\"entries\":[]} trailing", "{\"schemaVersion\":1,\"entries\":[}"] {
            XCTAssertNil(ShortcutCatalog.decode(Data(fixture.utf8)))
        }
    }

    func testCatalogDecodeEnforcesEntryCountBoundary() throws {
        let accepted = try JSONEncoder().encode(makeCatalog(Array(1...128)))
        let rejected = try JSONEncoder().encode(makeCatalog(Array(1...129)))
        XCTAssertLessThan(rejected.count, 32_768, "The count fixture must not fail only because of bytes")
        XCTAssertEqual(ShortcutCatalog.decode(accepted)?.entries.count, 128)
        XCTAssertNil(ShortcutCatalog.decode(rejected))
    }

    func testAliasRejectsInvisibleCharactersBeforeTrimming() throws {
        let rejected = [
            "", "   ", "\tSlot 1", "Slot 1\n", "Slot\r1", "Slot\u{0000}1",
            "Slot\u{007F}1", "Slot\u{200B}1", "Slot\u{FEFF}1", "Slot\u{200E}1",
            "Slot\u{2028}1", "Slot\u{2029}1"
        ]
        for (index, alias) in rejected.enumerated() {
            XCTAssertNil(ShortcutCatalog.normalizedAlias(alias), "Fixture \(index)")
            let data = try jsonData(["schemaVersion": 1, "entries": [["id": identifier(1).uuidString, "alias": alias]]])
            XCTAssertNil(ShortcutCatalog.decode(data), "Fixture \(index)")
        }
    }

    func testAliasNormalizesNFCAndTrimsBeforeLengthLimits() throws {
        let decomposed = "  Cafe\u{0301}  "
        let normalized = try XCTUnwrap(ShortcutCatalog.normalizedAlias(decomposed))
        XCTAssertEqual(Array(normalized.utf8), Array("Café".utf8))
        let data = try jsonData(["schemaVersion": 1, "entries": [["id": identifier(1).uuidString, "alias": decomposed]]])
        let decodedAlias = try XCTUnwrap(ShortcutCatalog.decode(data)?.entries.first?.alias)
        XCTAssertEqual(Array(decodedAlias.utf8), Array("Café".utf8))
        let padded = String(repeating: " ", count: 500) + String(repeating: "x", count: 80) + String(repeating: " ", count: 500)
        XCTAssertEqual(ShortcutCatalog.normalizedAlias(padded), String(repeating: "x", count: 80))
        let decomposedHangul = String(repeating: "\u{1100}\u{1161}\u{11A8}", count: 80)
        XCTAssertGreaterThan(decomposedHangul.utf8.count, 256)
        let hangul = try XCTUnwrap(ShortcutCatalog.normalizedAlias(decomposedHangul))
        XCTAssertEqual(Array(hangul.utf8), Array(String(repeating: "각", count: 80).utf8))
    }

    func testAliasEnforcesCharacterAndUTF8LimitsIndependently() {
        XCTAssertNotNil(ShortcutCatalog.normalizedAlias(String(repeating: "x", count: 80)))
        XCTAssertNil(ShortcutCatalog.normalizedAlias(String(repeating: "x", count: 81)))
        XCTAssertNotNil(ShortcutCatalog.normalizedAlias(String(repeating: "界", count: 80)))
        let atByteLimit = String(repeating: "😀", count: 64)
        let overByteLimit = String(repeating: "😀", count: 65)
        XCTAssertEqual(atByteLimit.utf8.count, 256)
        XCTAssertLessThan(overByteLimit.count, 80)
        XCTAssertNotNil(ShortcutCatalog.normalizedAlias(atByteLimit))
        XCTAssertNil(ShortcutCatalog.normalizedAlias(overByteLimit))
    }

    func testInternationalAliasPreservesJoinersAndNFCBytesAcrossRoundTrip() throws {
        let input = "  中文👩\u{200D}💻 ك\u{200C}ا Cafe\u{0301}  "
        let expected = "中文👩\u{200D}💻 ك\u{200C}ا Café"
        let normalized = try XCTUnwrap(ShortcutCatalog.normalizedAlias(input))
        XCTAssertEqual(Array(normalized.utf8), Array(expected.utf8))
        let raw = try jsonData(["schemaVersion": 1, "entries": [["id": identifier(1).uuidString, "alias": input]]])
        let decoded = try XCTUnwrap(ShortcutCatalog.decode(raw))
        let alias = try XCTUnwrap(decoded.entries.first?.alias)
        XCTAssertEqual(Array(alias.utf8), Array(expected.utf8))
        let encoded = try JSONEncoder().encode(decoded)
        let roundTrip = try XCTUnwrap(ShortcutCatalog.decode(encoded)?.entries.first?.alias)
        XCTAssertEqual(Array(roundTrip.utf8), Array(expected.utf8))
        let entry = ShortcutCatalog.Entry(id: identifier(1), alias: "Cafe\u{0301}")
        XCTAssertEqual(Array(entry.alias.utf8), Array("Café".utf8))
    }

    func testSuiteOverrideValidationIsPureAndFailsClosed() {
        for valid in ["com.aethernative.aetherscreens.shortcutsqa", "com.aethernative.qa-1"] {
            XCTAssertEqual(ShortcutCatalogReader.validatedSuiteName(valid), valid)
        }
        let invalid: [Any?] = [
            nil, 1, true, Data(), ["com.aethernative.qa"], "", "org.aethernative.qa",
            "com.aethernative", "com.aethernative.", "com.aethernative..qa",
            "com.aethernative.-qa", "com.aethernative.qa-", "com.aethernative.qa\n",
            "com.aethernative.qa\u{200B}", "com.aethernative." + String(repeating: "x", count: 64),
            "com.aethernative." + Array(repeating: String(repeating: "x", count: 63), count: 4).joined(separator: ".")
        ]
        for (index, value) in invalid.enumerated() {
            XCTAssertEqual(ShortcutCatalogReader.validatedSuiteName(value), ShortcutCatalogReader.defaultSuiteName, "Fixture \(index)")
        }
    }

    func testReaderFreshReadsNeverWriteAndInvalidReturnsEmpty() throws {
        let memory = ShortcutTestMemory()
        let reader = ShortcutCatalogReader(readData: { memory.read() })
        let fixtures: [(Data?, [UUID])] = [
            (nil, []), (Data(), []), (Data("invalid JSON".utf8), []),
            (try JSONEncoder().encode(makeCatalog([1])), [identifier(1)]),
            (try jsonData(["schemaVersion": 2, "entries": []]), []),
            (try JSONEncoder().encode(makeCatalog([2])), [identifier(2)])
        ]
        for (fixture, expectedIDs) in fixtures {
            memory.replaceSeed(fixture)
            let result = reader.read()
            XCTAssertEqual(result.schemaVersion, 1)
            XCTAssertEqual(result.entries.map(\.id), expectedIDs)
            XCTAssertTrue(memory.snapshot.writes.isEmpty)
            XCTAssertEqual(memory.snapshot.data, fixture)
        }
        XCTAssertEqual(memory.snapshot.reads, fixtures.count)
    }

    func testStoreInvalidAliasLeavesWriterAndStateUntouched() throws {
        let seed = try JSONEncoder().encode(makeCatalog([1]))
        let memory = ShortcutTestMemory(seed: seed)
        let store = makeStore(memory)
        let previous = store.catalog.entries
        for alias in ["", "  ", "Slot\n1", String(repeating: "x", count: 81), String(repeating: "😀", count: 65)] {
            XCTAssertThrowsError(try store.setAlias(alias, for: identifier(1)))
            XCTAssertEqual(store.catalog.entries, previous)
            XCTAssertEqual(memory.snapshot.data, seed)
            XCTAssertTrue(memory.snapshot.writes.isEmpty)
        }
        XCTAssertEqual(memory.snapshot.reads, 1)
    }

    func testStoreCanonicalAliasUpdatesOnceAndPersistsOnlyProjection() throws {
        let memory = ShortcutTestMemory()
        let store = makeStore(memory)
        try store.setAlias("  Cafe\u{0301}  ", for: identifier(1))
        let alias = try XCTUnwrap(store.entry(for: identifier(1))?.alias)
        XCTAssertEqual(Array(alias.utf8), Array("Café".utf8))
        XCTAssertEqual(memory.snapshot.writes.count, 1)
        try assertProjection(try XCTUnwrap(memory.snapshot.data), expectedIDs: [identifier(1)])
        try store.setAlias("Café", for: identifier(1))
        XCTAssertEqual(memory.snapshot.writes.count, 1, "An equivalent normalized alias must not write again")
        XCTAssertNil(store.entry(for: identifier(2)))
    }

    func testStoreRemovalAndPruningPersistOnlyChanges() throws {
        let memory = ShortcutTestMemory(seed: try JSONEncoder().encode(makeCatalog([1, 2, 3])))
        let store = makeStore(memory)
        store.remove(id: identifier(99))
        store.prune(availableIDs: [identifier(1), identifier(2), identifier(3), identifier(99)])
        XCTAssertTrue(memory.snapshot.writes.isEmpty)
        store.remove(id: identifier(2))
        XCTAssertNil(store.entry(for: identifier(2)))
        XCTAssertEqual(store.catalog.entries.map(\.id), [identifier(1), identifier(3)])
        XCTAssertEqual(memory.snapshot.writes.count, 1)
        try assertProjection(try XCTUnwrap(memory.snapshot.data), expectedIDs: [identifier(1), identifier(3)])
        store.remove(id: identifier(2))
        store.prune(availableIDs: [identifier(3)])
        XCTAssertEqual(memory.snapshot.writes.count, 2)
        XCTAssertEqual(store.catalog.entries.map(\.id), [identifier(3)])
        store.prune(availableIDs: [])
        XCTAssertEqual(memory.snapshot.writes.count, 3)
        XCTAssertTrue(store.catalog.entries.isEmpty)
        try assertProjection(try XCTUnwrap(memory.snapshot.data), expectedIDs: [])
        store.prune(availableIDs: [])
        XCTAssertEqual(memory.snapshot.writes.count, 3)
    }

    func testStoreEntryLimitAllowsRenameButRejectsNewEntry() throws {
        let memory = ShortcutTestMemory(seed: try JSONEncoder().encode(makeCatalog(Array(1...128))))
        let store = makeStore(memory)
        try store.setAlias("Renamed slot", for: identifier(1))
        XCTAssertEqual(store.catalog.entries.count, 128)
        XCTAssertEqual(store.entry(for: identifier(1))?.alias, "Renamed slot")
        let previous = store.catalog.entries
        let bytes = memory.snapshot.data
        XCTAssertThrowsError(try store.setAlias("New slot", for: identifier(129)))
        XCTAssertEqual(store.catalog.entries, previous)
        XCTAssertEqual(memory.snapshot.data, bytes)
        XCTAssertEqual(memory.snapshot.writes.count, 1)
    }

    func testStoreByteLimitRejectsOversizedMutationWithoutWrite() throws {
        let alias = String(repeating: "😀", count: 64)
        var entries: [ShortcutCatalog.Entry] = []
        for index in 1...128 {
            let candidate = entries + [.init(id: identifier(index), alias: alias)]
            if try JSONEncoder().encode(ShortcutCatalog(entries: candidate)).count > 32_768 { break }
            entries = candidate
        }
        XCTAssertFalse(entries.isEmpty)
        XCTAssertLessThan(entries.count, 128, "The byte fixture must reach the limit before the entry limit")
        let seed = try JSONEncoder().encode(ShortcutCatalog(entries: entries))
        let oversized = try JSONEncoder().encode(ShortcutCatalog(entries: entries + [.init(id: identifier(entries.count + 1), alias: alias)]))
        XCTAssertLessThanOrEqual(seed.count, 32_768)
        XCTAssertGreaterThan(oversized.count, 32_768)
        let memory = ShortcutTestMemory(seed: seed)
        let store = makeStore(memory)
        XCTAssertThrowsError(try store.setAlias(alias, for: identifier(entries.count + 1)))
        XCTAssertEqual(store.catalog.entries, entries)
        XCTAssertEqual(memory.snapshot.data, seed)
        XCTAssertTrue(memory.snapshot.writes.isEmpty)
    }

    func testStoreValidationNeverWritesAndSharesMutationFailureContract() throws {
        let validMemory = ShortcutTestMemory(seed: try JSONEncoder().encode(makeCatalog([1])))
        let validStore = makeStore(validMemory)
        let previous = validStore.catalog.entries
        let previousBytes = validMemory.snapshot.data
        XCTAssertNoThrow(try validStore.validateAlias(" New slot ", for: identifier(2)))
        XCTAssertNoThrow(try validStore.validateAlias("Slot 1", for: identifier(1)))
        XCTAssertEqual(validStore.catalog.entries, previous)
        XCTAssertEqual(validMemory.snapshot.data, previousBytes)
        XCTAssertTrue(validMemory.snapshot.writes.isEmpty)

        func assertRejectedWithoutWrite(_ memory: ShortcutTestMemory, alias: String, id: UUID) {
            let store = makeStore(memory)
            let entries = store.catalog.entries
            let bytes = memory.snapshot.data
            var validationFailure: Error?
            var mutationFailure: Error?
            XCTAssertThrowsError(try store.validateAlias(alias, for: id)) { validationFailure = $0 }
            XCTAssertEqual(store.catalog.entries, entries)
            XCTAssertEqual(memory.snapshot.data, bytes)
            XCTAssertTrue(memory.snapshot.writes.isEmpty)
            XCTAssertThrowsError(try store.setAlias(alias, for: id)) { mutationFailure = $0 }
            XCTAssertTrue(validationFailure is ShortcutCatalogStore.Failure)
            XCTAssertTrue(mutationFailure is ShortcutCatalogStore.Failure)
            let validationMessage = (validationFailure as? LocalizedError)?.errorDescription
            XCTAssertNotNil(validationMessage)
            XCTAssertEqual(validationMessage, (mutationFailure as? LocalizedError)?.errorDescription)
            XCTAssertEqual(store.catalog.entries, entries)
            XCTAssertEqual(memory.snapshot.data, bytes)
            XCTAssertTrue(memory.snapshot.writes.isEmpty)
        }

        assertRejectedWithoutWrite(ShortcutTestMemory(), alias: "Slot\n1", id: identifier(1))
        let fullMemory = ShortcutTestMemory(seed: try JSONEncoder().encode(makeCatalog(Array(1...128))))
        assertRejectedWithoutWrite(fullMemory, alias: "New slot", id: identifier(129))
        let largeAlias = String(repeating: "😀", count: 64)
        var entries: [ShortcutCatalog.Entry] = []
        for index in 1...128 {
            let candidate = entries + [.init(id: identifier(index), alias: largeAlias)]
            if try JSONEncoder().encode(ShortcutCatalog(entries: candidate)).count > 32_768 { break }
            entries = candidate
        }
        XCTAssertLessThan(entries.count, 128)
        let largeMemory = ShortcutTestMemory(seed: try JSONEncoder().encode(ShortcutCatalog(entries: entries)))
        assertRejectedWithoutWrite(largeMemory, alias: largeAlias, id: identifier(entries.count + 1))
    }

    func testQueueRequiresOptInAndRejectsInvalidProgrammaticProjection() throws {
        let id = identifier(1)
        let queue = ShortcutLaunchQueue(now: { 100 })
        let invalid = [
            ShortcutCatalog(),
            makeCatalog([2]),
            ShortcutCatalog(entries: [.init(id: id, alias: "Slot 1"), .init(id: id, alias: "Slot 2")]),
            ShortcutCatalog(entries: [.init(id: id, alias: " Slot 1 ")]),
            ShortcutCatalog(entries: [.init(id: id, alias: "Slot\n1")]),
            ShortcutCatalog(entries: [.init(id: id, alias: String(repeating: "x", count: 81))]),
            makeCatalog(Array(1...129)),
            ShortcutCatalog(entries: (1...128).map { .init(id: identifier($0), alias: String(repeating: "😀", count: 64)) })
        ]
        for catalog in invalid {
            XCTAssertThrowsError(try queue.enqueue(deviceID: id, catalog: catalog))
        }
        XCTAssertNil(queue.takeNext(isActive: true, isReady: true, catalog: makeCatalog([1]), availableIDs: [id]))
    }

    func testQueueDefersUntilActiveAndBootstrapReady() throws {
        let clock = ShortcutTestClock(100)
        let catalog = makeCatalog([1])
        let id = identifier(1)
        let queue = ShortcutLaunchQueue(now: { clock.value })
        let token = try queue.enqueue(deviceID: id, catalog: catalog)
        clock.value = 101
        XCTAssertNil(queue.takeNext(isActive: false, isReady: true, catalog: catalog, availableIDs: [id]))
        XCTAssertNil(queue.takeNext(isActive: true, isReady: false, catalog: catalog, availableIDs: [id]))
        XCTAssertNil(queue.takeNext(isActive: false, isReady: false, catalog: catalog, availableIDs: [id]))
        let request = try XCTUnwrap(queue.takeNext(isActive: true, isReady: true, catalog: catalog, availableIDs: [id]))
        XCTAssertEqual(request.token, token)
        XCTAssertEqual(request.deviceID, id)
        XCTAssertEqual(request.createdAt, 100)
        XCTAssertNil(queue.takeNext(isActive: true, isReady: true, catalog: catalog, availableIDs: [id]))
    }

    func testQueueExpiresAtLifetimeBoundaryEvenWhileInactive() throws {
        let clock = ShortcutTestClock(100)
        let catalog = makeCatalog([1])
        let id = identifier(1)
        let before = ShortcutLaunchQueue(now: { clock.value }, lifetime: 10)
        let beforeToken = try before.enqueue(deviceID: id, catalog: catalog)
        clock.value = 109.999
        XCTAssertNil(before.takeNext(isActive: false, isReady: true, catalog: catalog, availableIDs: [id]))
        XCTAssertEqual(before.takeNext(isActive: true, isReady: true, catalog: catalog, availableIDs: [id])?.token, beforeToken)
        clock.value = 100
        let atBoundary = ShortcutLaunchQueue(now: { clock.value }, lifetime: 10)
        try atBoundary.enqueue(deviceID: id, catalog: catalog)
        clock.value = 110
        XCTAssertNil(atBoundary.takeNext(isActive: false, isReady: false, catalog: catalog, availableIDs: [id]))
        clock.value = 111
        XCTAssertNil(atBoundary.takeNext(isActive: true, isReady: true, catalog: catalog, availableIDs: [id]))
    }

    func testQueueDuplicateDoesNotRenewTokenOrLifetime() throws {
        let clock = ShortcutTestClock(100)
        let catalog = makeCatalog([1])
        let id = identifier(1)
        let inspect = ShortcutLaunchQueue(now: { clock.value })
        let expire = ShortcutLaunchQueue(now: { clock.value })
        let token = try inspect.enqueue(deviceID: id, catalog: catalog)
        let expiringToken = try expire.enqueue(deviceID: id, catalog: catalog)
        clock.value = 120
        XCTAssertEqual(try inspect.enqueue(deviceID: id, catalog: catalog), token)
        XCTAssertEqual(try expire.enqueue(deviceID: id, catalog: catalog), expiringToken)
        let request = try XCTUnwrap(inspect.takeNext(isActive: true, isReady: true, catalog: catalog, availableIDs: [id]))
        XCTAssertEqual(request.token, token)
        XCTAssertEqual(request.createdAt, 100)
        clock.value = 130
        XCTAssertNil(expire.takeNext(isActive: true, isReady: true, catalog: catalog, availableIDs: [id]))
    }

    func testQueueFullCapacityStillAllowsDuplicate() throws {
        let catalog = makeCatalog([1, 2])
        let queue = ShortcutLaunchQueue(now: { 100 }, capacity: 1)
        let token = try queue.enqueue(deviceID: identifier(1), catalog: catalog)
        XCTAssertEqual(try queue.enqueue(deviceID: identifier(1), catalog: catalog), token)
        XCTAssertThrowsError(try queue.enqueue(deviceID: identifier(2), catalog: catalog))
        XCTAssertEqual(queue.takeNext(isActive: true, isReady: true, catalog: catalog, availableIDs: [identifier(1), identifier(2)])?.token, token)
        XCTAssertNil(queue.takeNext(isActive: true, isReady: true, catalog: catalog, availableIDs: [identifier(1), identifier(2)]))
    }

    func testQueueCapacityClampsToZeroAndCatalogEntryLimit() throws {
        for capacity in [Int.min, -1, 0] {
            let queue = ShortcutLaunchQueue(now: { 100 }, capacity: capacity)
            XCTAssertThrowsError(try queue.enqueue(deviceID: identifier(1), catalog: makeCatalog([1])))
        }
        let catalog = makeCatalog(Array(1...128))
        let queue = ShortcutLaunchQueue(now: { 100 }, capacity: Int.max)
        for entry in catalog.entries { try queue.enqueue(deviceID: entry.id, catalog: catalog) }
        XCTAssertThrowsError(try queue.enqueue(deviceID: identifier(129), catalog: makeCatalog([129])))
        let availableIDs = Set(catalog.entries.map(\.id))
        var claimed: [UUID] = []
        while let request = queue.takeNext(isActive: true, isReady: true, catalog: catalog, availableIDs: availableIDs) {
            claimed.append(request.deviceID)
        }
        XCTAssertEqual(claimed, catalog.entries.map(\.id))
        XCTAssertEqual(Set(claimed).count, 128)
    }

    func testQueueDropsDisabledAndDeletedThenClaimsNextValid() throws {
        let original = makeCatalog([1, 2, 3])
        let queue = ShortcutLaunchQueue(now: { 100 })
        try queue.enqueue(deviceID: identifier(1), catalog: original)
        try queue.enqueue(deviceID: identifier(2), catalog: original)
        let validToken = try queue.enqueue(deviceID: identifier(3), catalog: original)
        let current = makeCatalog([2, 3])
        let available: Set<UUID> = [identifier(1), identifier(3)]
        let request = try XCTUnwrap(queue.takeNext(isActive: true, isReady: true, catalog: current, availableIDs: available))
        XCTAssertEqual(request.deviceID, identifier(3))
        XCTAssertEqual(request.token, validToken)
        XCTAssertNil(queue.takeNext(isActive: true, isReady: true, catalog: original, availableIDs: Set(original.entries.map(\.id))))
    }

    func testQueueConsumersClaimEachRequestExactlyOnceInFIFOOrder() throws {
        let catalog = makeCatalog([1, 2])
        let available: Set<UUID> = [identifier(1), identifier(2)]
        let queue = ShortcutLaunchQueue(now: { 100 })
        let firstToken = try queue.enqueue(deviceID: identifier(1), catalog: catalog)
        let secondToken = try queue.enqueue(deviceID: identifier(2), catalog: catalog)
        // Two ready scene consumers use the same MainActor claim boundary.
        let firstScene = { queue.takeNext(isActive: true, isReady: true, catalog: catalog, availableIDs: available) }
        let secondScene = { queue.takeNext(isActive: true, isReady: true, catalog: catalog, availableIDs: available) }
        let first = try XCTUnwrap(firstScene())
        let second = try XCTUnwrap(secondScene())
        XCTAssertEqual(first.token, firstToken)
        XCTAssertEqual(second.token, secondToken)
        XCTAssertEqual([first.deviceID, second.deviceID], [identifier(1), identifier(2)])
        XCTAssertNotEqual(first.token, second.token)
        XCTAssertNil(firstScene())
        XCTAssertNil(secondScene())
    }

    func testQueueCancelDoesNotDropAnotherDevice() throws {
        let catalog = makeCatalog([1, 2])
        let queue = ShortcutLaunchQueue(now: { 100 })
        try queue.enqueue(deviceID: identifier(1), catalog: catalog)
        let survivingToken = try queue.enqueue(deviceID: identifier(2), catalog: catalog)
        queue.cancel(deviceID: identifier(99))
        queue.cancel(deviceID: identifier(1))
        queue.cancel(deviceID: identifier(1))
        let available: Set<UUID> = [identifier(1), identifier(2)]
        let request = try XCTUnwrap(queue.takeNext(isActive: true, isReady: true, catalog: catalog, availableIDs: available))
        XCTAssertEqual(request.deviceID, identifier(2))
        XCTAssertEqual(request.token, survivingToken)
        XCTAssertNil(queue.takeNext(isActive: true, isReady: true, catalog: catalog, availableIDs: available))
    }

    func testQueueInvalidClockDropsPendingAndRejectsEnqueue() throws {
        let catalog = makeCatalog([1])
        let id = identifier(1)
        let invalidTimes: [TimeInterval] = [.nan, .infinity, -.infinity, -1]
        for time in invalidTimes {
            let clock = ShortcutTestClock(100)
            let queue = ShortcutLaunchQueue(now: { clock.value })
            try queue.enqueue(deviceID: id, catalog: catalog)
            clock.value = time
            XCTAssertNil(queue.takeNext(isActive: false, isReady: false, catalog: catalog, availableIDs: [id]))
            XCTAssertThrowsError(try queue.enqueue(deviceID: id, catalog: catalog))
            clock.value = 100
            XCTAssertNil(queue.takeNext(isActive: true, isReady: true, catalog: catalog, availableIDs: [id]))
        }
    }

    func testQueueBackwardClockCannotRevivePending() throws {
        let clock = ShortcutTestClock(100)
        let catalog = makeCatalog([1])
        let id = identifier(1)
        let queue = ShortcutLaunchQueue(now: { clock.value })
        try queue.enqueue(deviceID: id, catalog: catalog)
        clock.value = 90
        XCTAssertNil(queue.takeNext(isActive: false, isReady: false, catalog: catalog, availableIDs: [id]))
        clock.value = 105
        XCTAssertNil(queue.takeNext(isActive: true, isReady: true, catalog: catalog, availableIDs: [id]))
    }

    func testQueueInvalidLifetimeCannotAcceptRequests() {
        let catalog = makeCatalog([1])
        let invalidLifetimes: [TimeInterval] = [0, -1, .nan, .infinity, -.infinity]
        for lifetime in invalidLifetimes {
            let queue = ShortcutLaunchQueue(now: { 100 }, lifetime: lifetime)
            XCTAssertThrowsError(try queue.enqueue(deviceID: identifier(1), catalog: catalog))
            XCTAssertNil(queue.takeNext(isActive: true, isReady: true, catalog: catalog, availableIDs: [identifier(1)]))
        }
    }

    private func identifier(_ number: Int) -> UUID {
        let digits = String(number, radix: 16)
        return UUID(uuidString: "00000000-0000-4000-8000-" + String(repeating: "0", count: 12 - digits.count) + digits)!
    }

    private func makeCatalog(_ numbers: [Int]) -> ShortcutCatalog {
        ShortcutCatalog(entries: numbers.map { .init(id: identifier($0), alias: "Slot \($0)") })
    }

    private func makeStore(_ memory: ShortcutTestMemory) -> ShortcutCatalogStore {
        ShortcutCatalogStore(readData: { memory.read() }, writeData: { memory.write($0) })
    }

    private func jsonData(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func assertProjection(_ data: Data, expectedIDs: Set<UUID>, file: StaticString = #filePath, line: UInt = #line) throws {
        let object = try JSONSerialization.jsonObject(with: data)
        let root = try XCTUnwrap(object as? [String: Any], file: file, line: line)
        XCTAssertEqual(Set(root.keys), ["schemaVersion", "entries"], file: file, line: line)
        XCTAssertEqual(root["schemaVersion"] as? Int, 1, file: file, line: line)
        let entries = try XCTUnwrap(root["entries"] as? [[String: Any]], file: file, line: line)
        let ids = try entries.map { entry -> UUID in
            XCTAssertEqual(Set(entry.keys), ["id", "alias"], file: file, line: line)
            XCTAssertNotNil(entry["alias"] as? String, file: file, line: line)
            let value = try XCTUnwrap(entry["id"] as? String, file: file, line: line)
            return try XCTUnwrap(UUID(uuidString: value), file: file, line: line)
        }
        XCTAssertEqual(Set(ids), expectedIDs, file: file, line: line)
        XCTAssertEqual(ids.count, expectedIDs.count, file: file, line: line)
    }
}

private final class ShortcutTestClock {
    var value: TimeInterval

    init(_ value: TimeInterval) { self.value = value }
}

/// The reader's Sendable closure shares only this locked, synthetic memory fixture.
private final class ShortcutTestMemory: @unchecked Sendable {
    struct Snapshot {
        let data: Data?
        let reads: Int
        let writes: [Data]
    }

    private let lock = NSLock()
    private var data: Data?
    private var reads = 0
    private var writes: [Data] = []

    init(seed: Data? = nil) { data = seed }

    func read() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        reads += 1
        return data
    }

    func write(_ newData: Data) {
        lock.lock()
        defer { lock.unlock() }
        data = newData
        writes.append(newData)
    }

    func replaceSeed(_ newData: Data?) {
        lock.lock()
        defer { lock.unlock() }
        data = newData
    }

    var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(data: data, reads: reads, writes: writes)
    }
}
