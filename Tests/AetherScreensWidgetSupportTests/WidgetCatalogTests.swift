import Foundation
import XCTest
@testable import AetherScreensWidgetSupport

final class WidgetCatalogTests: XCTestCase {
    private let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    func testRoundTripContainsOnlyVersionIDsAndAliases() throws {
        let data = try XCTUnwrap(WidgetCatalog(entries: [.init(id: id, alias: "QA Computer")]).validatedData())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "entries"])
        let entry = try XCTUnwrap((object["entries"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(entry.keys), ["id", "alias"])
        let decoded = try XCTUnwrap(WidgetCatalog.decode(data))
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.entries, [.init(id: id, alias: "QA Computer")])
    }

    func testRejectsUnknownRootAndEntryFields() throws {
        for extra in ["host", "password", "port", "device"] {
            let root = try json(["schemaVersion": 1, "entries": [], extra: "synthetic"])
            XCTAssertNil(WidgetCatalog.decode(root), extra)
            let data = try json(["schemaVersion": 1, "entries": [["id": id.uuidString, "alias": "QA", extra: "synthetic"]]])
            XCTAssertNil(WidgetCatalog.decode(data), extra)
        }
    }

    func testRejectsDuplicateJSONKeysIncludingEscapedSpellings() {
        let samples = [
            #"{"schemaVersion":1,"schemaVersion":1,"entries":[]}"#,
            #"{"schemaVersion":1,"entries":[],"\u0065ntries":[]}"#,
            "{\"schemaVersion\":1,\"entries\":[{\"id\":\"\(id.uuidString)\",\"alias\":\"QA\",\"alias\":\"QA\"}]}",
            "{\"schemaVersion\":1,\"entries\":[{\"id\":\"\(id.uuidString)\",\"\\u0069d\":\"\(id.uuidString)\",\"alias\":\"QA\"}]}"
        ]
        for sample in samples { XCTAssertNil(WidgetCatalog.decode(Data(sample.utf8)), sample) }
    }

    func testRejectsDuplicateIDsRegardlessOfUUIDLetterCase() throws {
        let mixedID = UUID(uuidString: "ABCDEF01-2345-6789-ABCD-EF0123456789")!
        let data = try json(["schemaVersion": 1, "entries": [
            ["id": mixedID.uuidString, "alias": "QA One"],
            ["id": mixedID.uuidString.lowercased(), "alias": "QA Two"]
        ]])
        XCTAssertNil(WidgetCatalog.decode(data))
        XCTAssertNil(WidgetCatalog(entries: [.init(id: mixedID, alias: "QA One"), .init(id: mixedID, alias: "QA Two")]).validatedData())
    }

    func testRejectsWrongVersionMissingFieldsTypesAndTrailingContent() throws {
        let invalid: [Any] = [
            ["schemaVersion": 2, "entries": []], ["schemaVersion": "1", "entries": []],
            ["entries": []], ["schemaVersion": 1], ["schemaVersion": 1, "entries": "QA"],
            ["schemaVersion": 1, "entries": [["id": "not-a-uuid", "alias": "QA"]]],
            ["schemaVersion": 1, "entries": [["id": id.uuidString]]],
            ["schemaVersion": 1, "entries": [["id": id.uuidString, "alias": 7]]]
        ]
        for sample in invalid { XCTAssertNil(WidgetCatalog.decode(try json(sample))) }
        XCTAssertNil(WidgetCatalog.decode(nil))
        XCTAssertNil(WidgetCatalog.decode(Data()))
        XCTAssertNil(WidgetCatalog.decode(Data([0xFF])))
        let valid = try XCTUnwrap(WidgetCatalog().validatedData())
        XCTAssertNil(WidgetCatalog.decode(valid + Data(" {}".utf8)))
    }

    func testNormalizesNFCAndAllowsVisibleJoinedEmoji() throws {
        let decomposed = "Cafe\u{0301}"
        XCTAssertEqual(WidgetCatalog.normalizedAlias("  " + decomposed + "  "), "Café")
        let data = try json(["schemaVersion": 1, "entries": [["id": id.uuidString, "alias": decomposed]]])
        let catalog = try XCTUnwrap(WidgetCatalog.decode(data))
        XCTAssertEqual(Array(catalog.entries[0].alias.utf8), Array("Café".utf8))
        XCTAssertEqual(WidgetCatalog.normalizedAlias("QA 👩‍💻"), "QA 👩‍💻")
        XCTAssertNotNil(catalog.validatedData())
    }

    func testRejectsControlBidiAndInvisibleOnlyAliasesBeforeTrimming() throws {
        let invalid = ["", "   ", "\nQA", "QA\t", "QA\u{0000}", "QA\u{2028}",
                       "QA\u{2029}", "QA\u{202E}", "\u{200D}", "\u{0301}", "\u{E000}"]
        for alias in invalid {
            XCTAssertNil(WidgetCatalog.normalizedAlias(alias), alias.debugDescription)
            let data = try json(["schemaVersion": 1, "entries": [["id": id.uuidString, "alias": alias]]])
            XCTAssertNil(WidgetCatalog.decode(data), alias.debugDescription)
            XCTAssertNil(WidgetCatalog(entries: [.init(id: id, alias: alias)]).validatedData())
        }
        XCTAssertNil(WidgetCatalog(entries: [.init(id: id, alias: " QA ")]).validatedData(),
                     "A constructed writer must supply the normalized alias")
    }

    func testCharacterAndUTF8LimitsHaveIndependentInclusiveBoundaries() {
        XCTAssertNotNil(WidgetCatalog.normalizedAlias(String(repeating: "A", count: 80)))
        XCTAssertNil(WidgetCatalog.normalizedAlias(String(repeating: "A", count: 81)))
        XCTAssertNotNil(WidgetCatalog.normalizedAlias(String(repeating: "😀", count: 64)))
        XCTAssertNil(WidgetCatalog.normalizedAlias(String(repeating: "😀", count: 65)))
        let oneLargeGrapheme = "a" + String(repeating: "\u{0308}", count: 130)
        XCTAssertEqual(oneLargeGrapheme.count, 1)
        XCTAssertNil(WidgetCatalog.normalizedAlias(oneLargeGrapheme))
    }

    func testEntryAndEncodedByteLimitsFailClosed() throws {
        let entries = (0..<128).map { index in
            WidgetCatalog.Entry(id: UUID(), alias: "QA \(index)")
        }
        let maximum = try XCTUnwrap(WidgetCatalog(entries: entries).validatedData())
        XCTAssertEqual(WidgetCatalog.decode(maximum)?.entries.count, 128)
        let tooMany = WidgetCatalog(entries: entries + [.init(id: UUID(), alias: "QA Extra")])
        XCTAssertNil(tooMany.validatedData())
        XCTAssertNil(WidgetCatalog.decode(try JSONEncoder().encode(tooMany)))
        let wide = WidgetCatalog(entries: entries.map { .init(id: $0.id, alias: String(repeating: "😀", count: 64)) })
        let oversized = try JSONEncoder().encode(wide)
        XCTAssertGreaterThan(oversized.count, WidgetCatalog.maximumDataBytes)
        XCTAssertNil(wide.validatedData())
        XCTAssertNil(WidgetCatalog.decode(oversized))
        let empty = try XCTUnwrap(WidgetCatalog().validatedData())
        let exactLimit = empty + Data(repeating: 32, count: WidgetCatalog.maximumDataBytes - empty.count)
        XCTAssertNotNil(WidgetCatalog.decode(exactLimit))
        XCTAssertNil(WidgetCatalog.decode(exactLimit + Data([32])))
    }

    func testReaderReadsFreshDataAndInvalidProjectionNeverFallsBack() throws {
        let source = WidgetTestDataSource(try XCTUnwrap(WidgetCatalog(entries: [.init(id: id, alias: "QA Before")]).validatedData()))
        let reader = WidgetCatalogReader(readData: { source.read() })
        XCTAssertEqual(source.readCount, 0)
        XCTAssertEqual(reader.read().entries.first?.alias, "QA Before")
        source.set(try XCTUnwrap(WidgetCatalog(entries: [.init(id: id, alias: "QA After")]).validatedData()))
        XCTAssertEqual(reader.read().entries.first?.alias, "QA After")
        source.set(Data("broken".utf8))
        XCTAssertTrue(reader.read().entries.isEmpty)
        source.set(nil)
        XCTAssertTrue(reader.read().entries.isEmpty)
        XCTAssertEqual(source.readCount, 4)
    }

    private func json(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
    }
}

private final class WidgetTestDataSource: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private var count = 0
    init(_ data: Data?) { self.data = data }
    func set(_ data: Data?) { lock.lock(); self.data = data; lock.unlock() }
    func read() -> Data? { lock.lock(); defer { lock.unlock() }; count += 1; return data }
    var readCount: Int { lock.lock(); defer { lock.unlock() }; return count }
}
