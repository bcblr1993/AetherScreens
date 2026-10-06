import Foundation

/// The host is the writer; the extension reads the same bounded, atomic file.
public enum WidgetSharedStorage {
    public static let groupIdentifier = "group.com.aethernative.aetherscreens"
    public static let qaGroupIdentifier = "group.com.aethernative.aetherscreens.widgetqa"
    public static let storageKey = "com.aethernative.aetherscreens.widgets.catalog.v1"
    public static let catalogFileName = "widget-catalog-v1.json"
    public static let kind = "com.aethernative.aetherscreens.quickconnect"

    public enum Failure: Error, Equatable, Sendable {
        case unconfiguredGroup
        case unavailableContainer
        case invalidCatalog
        case unavailableExistingCatalog
    }

    public static func configuredGroupIdentifier(_ value: Any?) -> String? {
        guard let value = value as? String,
              value == groupIdentifier || value == qaGroupIdentifier else { return nil }
        return value
    }

    public static func read() -> Data? {
        try? readForEditing()
    }

    /// Editors may treat only a genuinely missing catalog as an empty projection.
    public static func readForEditing() throws -> Data? {
        guard let identifier = configuredGroupIdentifier(Bundle.main.object(forInfoDictionaryKey: "AetherScreensWidgetGroupIdentifier")) else {
            throw Failure.unconfiguredGroup
        }
        guard let container = containerURL(for: identifier) else { throw Failure.unavailableContainer }
        return try readForEditing(fileURL: container.appendingPathComponent(catalogFileName, isDirectory: false))
    }

    public static func write(_ data: Data) throws {
        guard WidgetCatalog.decode(data)?.validatedData() != nil else { throw Failure.invalidCatalog }
        guard let identifier = configuredGroupIdentifier(Bundle.main.object(forInfoDictionaryKey: "AetherScreensWidgetGroupIdentifier")) else {
            throw Failure.unconfiguredGroup
        }
        guard let container = containerURL(for: identifier) else { throw Failure.unavailableContainer }
        try write(data, fileURL: container.appendingPathComponent(catalogFileName, isDirectory: false))
    }

    private static func containerURL(for identifier: String) -> URL? {
        #if canImport(Darwin)
        // This public API supplies the authorized container; there is no directory fallback.
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        #else
        return nil
        #endif
    }

    /// Internal injection uses exactly the production IO with only a test-owned URL.
    /// Keep invalid/oversized bytes nonnil so an editor can fail closed instead of replacing them.
    static func read(fileURL: URL) -> Data? {
        try? readForEditing(fileURL: fileURL)
    }

    static func readForEditing(fileURL: URL) throws -> Data? {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: fileURL.deletingLastPathComponent().path, isDirectory: &isDirectory),
              isDirectory.boolValue else { throw Failure.unavailableContainer }
        do {
            return try boundedData(fileURL: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    static func write(_ data: Data, fileURL: URL) throws {
        guard let catalog = WidgetCatalog.decode(data), let validData = catalog.validatedData() else {
            throw Failure.invalidCatalog
        }
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: fileURL.deletingLastPathComponent().path, isDirectory: &isDirectory),
              isDirectory.boolValue else { throw Failure.unavailableContainer }
        do {
            if let existing = try readForEditing(fileURL: fileURL), WidgetCatalog.decode(existing) == nil {
                throw Failure.unavailableExistingCatalog
            }
        } catch {
            throw Failure.unavailableExistingCatalog
        }
        #if os(iOS)
        try validData.write(to: fileURL, options: [.atomic, .completeFileProtection])
        #else
        try validData.write(to: fileURL, options: .atomic)
        #endif
    }

    private static func boundedData(fileURL: URL) throws -> Data {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw Failure.unavailableExistingCatalog
        }
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let limit = WidgetCatalog.maximumDataBytes + 1
        var data = Data()
        while data.count < limit {
            guard let chunk = try handle.read(upToCount: min(4096, limit - data.count)), !chunk.isEmpty else { break }
            data.append(chunk)
        }
        return data
    }
}
