import Foundation
import Combine

/// The only saved information exposed to a native shortcut query.
public struct ShortcutCatalog: Codable, Sendable {
    public static let maximumEntries = 128
    public static let maximumDataBytes = 32_768
    public static let maximumAliasCharacters = 80
    public static let maximumAliasUTF8Bytes = 256

    public struct Entry: Codable, Hashable, Identifiable, Sendable {
        public let id: UUID
        public let alias: String

        public init(id: UUID, alias: String) {
            self.id = id
            self.alias = alias.precomposedStringWithCanonicalMapping
        }

        private enum CodingKeys: String, CodingKey { case id, alias }

        public init(from decoder: Decoder) throws {
            try ShortcutCatalog.requireKeys(["id", "alias"], in: decoder)
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(UUID.self, forKey: .id)
            guard let normalized = ShortcutCatalog.normalizedAlias(try values.decode(String.self, forKey: .alias)) else {
                throw ShortcutCatalog.invalidData(at: decoder.codingPath)
            }
            alias = normalized
        }
    }

    public let schemaVersion: Int
    public let entries: [Entry]

    public init(entries: [Entry] = []) {
        schemaVersion = 1
        self.entries = entries
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, entries }

    public init(from decoder: Decoder) throws {
        try Self.requireKeys(["schemaVersion", "entries"], in: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        entries = try values.decode([Entry].self, forKey: .entries)
        guard schemaVersion == 1, entries.count <= Self.maximumEntries,
              Set(entries.map(\.id)).count == entries.count else {
            throw Self.invalidData(at: decoder.codingPath)
        }
    }

    public static func decode(_ data: Data?) -> ShortcutCatalog? {
        guard let data, !data.isEmpty, data.count <= maximumDataBytes,
              String(data: data, encoding: .utf8) != nil else { return nil }
        var keys = ShortcutJSONKeyValidator(data: data)
        guard keys.validate() else { return nil }
        return try? JSONDecoder().decode(ShortcutCatalog.self, from: data)
    }

    public static func normalizedAlias(_ alias: String) -> String? {
        // Reject controls before trimming; a newline must not become a valid alias.
        guard alias.unicodeScalars.allSatisfy({ scalar in
            switch scalar.properties.generalCategory {
            case .format: return scalar.value == 0x200C || scalar.value == 0x200D
            case .control, .lineSeparator, .paragraphSeparator: return false
            default: return true
            }
        }) else { return nil }
        let normalized = alias.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= maximumAliasCharacters,
              normalized.utf8.count <= maximumAliasUTF8Bytes else { return nil }
        // Joiners and combining marks may accompany a visible letter or emoji,
        // but must not produce an empty-looking title on their own.
        guard normalized.unicodeScalars.contains(where: { scalar in
            guard !scalar.properties.isDefaultIgnorableCodePoint else { return false }
            switch scalar.properties.generalCategory {
            case .format, .control, .nonspacingMark, .spacingMark, .enclosingMark,
                 .spaceSeparator, .lineSeparator, .paragraphSeparator,
                 .unassigned, .surrogate, .privateUse:
                return false
            default:
                return true
            }
        }) else { return nil }
        return normalized
    }

    // Also validate programmatically constructed catalogs at the launch boundary.
    var validatedIDs: Set<UUID>? {
        guard schemaVersion == 1, entries.count <= Self.maximumEntries,
              entries.allSatisfy({ entry in
                  guard let normalized = Self.normalizedAlias(entry.alias) else { return false }
                  return normalized.utf8.elementsEqual(entry.alias.utf8)
              }) else { return nil }
        let ids = Set(entries.map(\.id))
        guard ids.count == entries.count,
              let data = try? JSONEncoder().encode(self), data.count <= Self.maximumDataBytes else { return nil }
        return ids
    }

    private static func requireKeys(_ expected: Set<String>, in decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: ShortcutCatalogKey.self)
        guard Set(values.allKeys.map(\.stringValue)) == expected else {
            throw invalidData(at: decoder.codingPath)
        }
    }

    private static func invalidData(at path: [CodingKey]) -> DecodingError {
        .dataCorrupted(.init(codingPath: path, debugDescription: "Invalid shortcut catalog."))
    }
}

/// Reading the independent projection never initializes the full device library.
public struct ShortcutCatalogReader: Sendable {
    public static let defaultSuiteName = "com.aethernative.aetherscreens"
    public static let storageKey = "com.aethernative.aetherscreens.shortcuts.catalog.v1"
    public static var suiteName: String {
        validatedSuiteName(Bundle.main.object(forInfoDictionaryKey: "AetherScreensShortcutCatalogSuite"))
    }
    private let readData: @Sendable () -> Data?

    public init(readData: @escaping @Sendable () -> Data?) {
        self.readData = readData
    }

    public func read() -> ShortcutCatalog {
        ShortcutCatalog.decode(readData()) ?? ShortcutCatalog()
    }

    public static func standard() -> ShortcutCatalogReader {
        ShortcutCatalogReader {
            UserDefaults(suiteName: suiteName)?.data(forKey: storageKey)
        }
    }

    // Kept pure so tests can validate isolation without reading real app defaults.
    static func validatedSuiteName(_ value: Any?) -> String {
        guard let value = value as? String, value.hasPrefix("com.aethernative."),
              value.utf8.count <= 255 else { return defaultSuiteName }
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard components.allSatisfy({ component in
            guard !component.isEmpty, component.utf8.count <= 63,
                  let first = component.utf8.first, let last = component.utf8.last,
                  isSuiteAlphanumeric(first), isSuiteAlphanumeric(last) else { return false }
            return component.utf8.allSatisfy { isSuiteAlphanumeric($0) || $0 == 45 }
        }) else { return defaultSuiteName }
        return value
    }

    private static func isSuiteAlphanumeric(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte)
    }
}

/// Only an explicit foreground app edit writes the shortcut projection.
@MainActor
public final class ShortcutCatalogStore: ObservableObject {
    public enum Failure: Error, LocalizedError, Sendable {
        case invalidAlias, full, tooLarge

        public var errorDescription: String? {
            switch self {
            case .invalidAlias: return "Enter a shortcut name with 1 to 80 visible characters."
            case .full: return "Too many computers are enabled for Shortcuts."
            case .tooLarge: return "The shortcut catalog is full. Use shorter shortcut names."
            }
        }
    }

    public static let shared = ShortcutCatalogStore(
        readData: { UserDefaults(suiteName: ShortcutCatalogReader.suiteName)?.data(forKey: ShortcutCatalogReader.storageKey) },
        writeData: { UserDefaults(suiteName: ShortcutCatalogReader.suiteName)?.set($0, forKey: ShortcutCatalogReader.storageKey) }
    )

    @Published public private(set) var catalog: ShortcutCatalog
    private let writeData: (Data) -> Void

    public init(readData: @escaping @Sendable () -> Data?, writeData: @escaping (Data) -> Void) {
        catalog = ShortcutCatalogReader(readData: readData).read()
        self.writeData = writeData
    }

    public func validateAlias(_ alias: String, for id: UUID) throws {
        _ = try encodedCandidate(alias, for: id)
    }

    public func setAlias(_ alias: String, for id: UUID) throws {
        guard let candidate = try encodedCandidate(alias, for: id) else { return }
        writeData(candidate.data)
        catalog = candidate.catalog
    }

    private func encodedCandidate(_ alias: String, for id: UUID) throws -> (catalog: ShortcutCatalog, data: Data)? {
        guard let alias = ShortcutCatalog.normalizedAlias(alias) else { throw Failure.invalidAlias }
        if entry(for: id)?.alias == alias { return nil }
        var entries = catalog.entries.filter { $0.id != id }
        guard entries.count < ShortcutCatalog.maximumEntries else { throw Failure.full }
        entries.append(.init(id: id, alias: alias))
        entries.sort { $0.id.uuidString < $1.id.uuidString }
        let candidate = ShortcutCatalog(entries: entries)
        guard let data = try? JSONEncoder().encode(candidate),
              data.count <= ShortcutCatalog.maximumDataBytes else { throw Failure.tooLarge }
        return (candidate, data)
    }

    public func remove(id: UUID) {
        saveRemoval(catalog.entries.filter { $0.id != id })
    }

    public func prune(availableIDs: Set<UUID>) {
        saveRemoval(catalog.entries.filter { availableIDs.contains($0.id) })
    }

    public func entry(for id: UUID) -> ShortcutCatalog.Entry? {
        catalog.entries.first { $0.id == id }
    }

    private func saveRemoval(_ entries: [ShortcutCatalog.Entry]) {
        guard entries != catalog.entries else { return }
        let candidate = ShortcutCatalog(entries: entries)
        guard let data = try? JSONEncoder().encode(candidate),
              data.count <= ShortcutCatalog.maximumDataBytes else { return }
        writeData(data)
        catalog = candidate
    }
}

private struct ShortcutCatalogKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

/// Foundation decoders fold duplicate object keys. Reject them before decoding.
private struct ShortcutJSONKeyValidator {
    private let bytes: [UInt8]
    private var index = 0

    init(data: Data) { bytes = Array(data) }

    mutating func validate() -> Bool {
        guard value(depth: 0) else { return false }
        skipWhitespace()
        return index == bytes.count
    }

    private mutating func value(depth: Int) -> Bool {
        guard depth <= 8 else { return false }
        skipWhitespace()
        guard index < bytes.count else { return false }
        switch bytes[index] {
        case 123: return object(depth: depth)
        case 91: return array(depth: depth)
        case 34: return string() != nil
        default:
            let start = index
            while index < bytes.count, ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
            return index > start
        }
    }

    private mutating func object(depth: Int) -> Bool {
        index += 1
        skipWhitespace()
        if consume(125) { return true }
        var keys = Set<String>()
        while true {
            guard let key = string(), keys.insert(key).inserted else { return false }
            skipWhitespace()
            guard consume(58), value(depth: depth + 1) else { return false }
            skipWhitespace()
            if consume(125) { return true }
            guard consume(44) else { return false }
            skipWhitespace()
        }
    }

    private mutating func array(depth: Int) -> Bool {
        index += 1
        skipWhitespace()
        if consume(93) { return true }
        while true {
            guard value(depth: depth + 1) else { return false }
            skipWhitespace()
            if consume(93) { return true }
            guard consume(44) else { return false }
        }
    }

    private mutating func string() -> String? {
        guard consume(34) else { return nil }
        let start = index - 1
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 34 {
                return try? JSONDecoder().decode(String.self, from: Data(bytes[start..<index]))
            }
            if byte == 92 {
                guard index < bytes.count else { return nil }
                index += 1
            } else if byte < 32 { return nil }
        }
        return nil
    }

    private mutating func skipWhitespace() {
        while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }
}
