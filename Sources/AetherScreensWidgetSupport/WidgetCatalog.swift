import Foundation

/// The widget receives only explicitly selected IDs and display aliases.
public struct WidgetCatalog: Codable, Sendable {
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
            try WidgetCatalog.requireKeys(["id", "alias"], in: decoder)
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(UUID.self, forKey: .id)
            guard let value = WidgetCatalog.normalizedAlias(try values.decode(String.self, forKey: .alias)) else {
                throw WidgetCatalog.invalidData(at: decoder.codingPath)
            }
            alias = value
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

    public static func decode(_ data: Data?) -> WidgetCatalog? {
        guard let data, !data.isEmpty, data.count <= maximumDataBytes,
              String(data: data, encoding: .utf8) != nil else { return nil }
        var validator = WidgetJSONKeyValidator(data: data)
        guard validator.validate() else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    /// Checks constructed values as well as values decoded from an untrusted file.
    public func validatedData() -> Data? {
        guard schemaVersion == 1, entries.count <= Self.maximumEntries,
              Set(entries.map(\.id)).count == entries.count,
              entries.allSatisfy({ entry in
                  guard let alias = Self.normalizedAlias(entry.alias) else { return false }
                  return alias.utf8.elementsEqual(entry.alias.utf8)
              }) else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self), data.count <= Self.maximumDataBytes else { return nil }
        return data
    }

    public static func normalizedAlias(_ alias: String) -> String? {
        // Check before trimming so whitespace does not hide a control character.
        guard alias.unicodeScalars.allSatisfy({ scalar in
            switch scalar.properties.generalCategory {
            case .format: return scalar.value == 0x200C || scalar.value == 0x200D
            case .control, .lineSeparator, .paragraphSeparator: return false
            default: return true
            }
        }) else { return nil }
        let value = alias.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= maximumAliasCharacters,
              value.utf8.count <= maximumAliasUTF8Bytes,
              value.unicodeScalars.contains(where: { scalar in
                  guard !scalar.properties.isDefaultIgnorableCodePoint else { return false }
                  switch scalar.properties.generalCategory {
                  case .format, .control, .nonspacingMark, .spacingMark, .enclosingMark,
                       .spaceSeparator, .lineSeparator, .paragraphSeparator,
                       .unassigned, .surrogate, .privateUse: return false
                  default: return true
                  }
              }) else { return nil }
        return value
    }

    private static func requireKeys(_ expected: Set<String>, in decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: WidgetCatalogKey.self)
        guard Set(values.allKeys.map(\.stringValue)) == expected else {
            throw invalidData(at: decoder.codingPath)
        }
    }

    private static func invalidData(at path: [CodingKey]) -> DecodingError {
        .dataCorrupted(.init(codingPath: path, debugDescription: "Invalid widget catalog."))
    }
}

private struct WidgetCatalogKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

/// JSONDecoder folds duplicate object keys; check their decoded spellings first.
private struct WidgetJSONKeyValidator {
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
