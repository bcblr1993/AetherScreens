import Foundation
import Combine
import AetherScreensWidgetSupport
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Foreground, explicit opt-in edits publish only a UUID and the chosen alias.
/// Widget readers never initialize the device library or credential storage.
@MainActor
public final class WidgetCatalogStore: ObservableObject {
    public enum Failure: Error, Equatable {
        case invalidAlias, full, unavailable
    }

    @Published public private(set) var catalog: WidgetCatalog
    private let reader: WidgetCatalogReader
    private let editingReader: () throws -> Data?
    private let writeData: (Data) throws -> Void
    private let reloadTimelines: () -> Void

    public init(readData: @escaping @Sendable () -> Data?,
                writeData: @escaping (Data) throws -> Void,
                reloadTimelines: @escaping () -> Void = {},
                readForEditing: (() throws -> Data?)? = nil) {
        reader = WidgetCatalogReader(readData: readData)
        self.editingReader = readForEditing ?? { readData() }
        catalog = reader.read()
        self.writeData = writeData
        self.reloadTimelines = reloadTimelines
    }

    public static func standardIfConfigured() -> WidgetCatalogStore? {
        guard WidgetSharedStorage.configuredGroupIdentifier(
            Bundle.main.object(forInfoDictionaryKey: "AetherScreensWidgetGroupIdentifier")) != nil else { return nil }
        return WidgetCatalogStore(readData: { WidgetSharedStorage.read() },
                                  writeData: { try WidgetSharedStorage.write($0) },
                                  reloadTimelines: {
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetSharedStorage.kind)
            #endif
        }, readForEditing: { try WidgetSharedStorage.readForEditing() })
    }

    public func entry(for id: UUID) -> WidgetCatalog.Entry? {
        catalog.entries.first { $0.id == id }
    }

    public func reloadForEditing() throws {
        catalog = try currentCatalog()
    }

    /// Read the opt-in again at both enqueue and foreground claim boundaries.
    public func freshLaunchCatalog() -> ShortcutCatalog {
        let current = reader.read()
        return ShortcutCatalog(entries: current.entries.map { .init(id: $0.id, alias: $0.alias) })
    }

    public func validateAlias(_ alias: String, for id: UUID) throws {
        _ = try candidate(alias, for: id)
    }

    public func setAlias(_ alias: String, for id: UUID) throws {
        let value = try candidate(alias, for: id)
        try save(value)
    }

    public func remove(id: UUID) throws {
        let current = try currentCatalog()
        try save(WidgetCatalog(entries: current.entries.filter { $0.id != id }))
    }

    public func prune(availableIDs: Set<UUID>) throws {
        let current = try currentCatalog()
        try save(WidgetCatalog(entries: current.entries.filter { availableIDs.contains($0.id) }))
    }

    private func candidate(_ alias: String, for id: UUID) throws -> WidgetCatalog {
        guard let alias = WidgetCatalog.normalizedAlias(alias) else { throw Failure.invalidAlias }
        var entries = try currentCatalog().entries.filter { $0.id != id }
        guard entries.count < WidgetCatalog.maximumEntries else { throw Failure.full }
        entries.append(.init(id: id, alias: alias))
        entries.sort { $0.id.uuidString < $1.id.uuidString }
        let value = WidgetCatalog(entries: entries)
        guard value.validatedData() != nil else { throw Failure.full }
        return value
    }

    private func save(_ value: WidgetCatalog) throws {
        guard let data = value.validatedData() else { throw Failure.full }
        let previous = try currentCatalog()
        guard previous.entries != value.entries else {
            catalog = previous
            return
        }
        // A failed or unavailable App Group cannot become a successful opt-in.
        do { try writeData(data) }
        catch { throw Failure.unavailable }
        catalog = value
        reloadTimelines()
    }

    private func currentCatalog() throws -> WidgetCatalog {
        let data: Data?
        do { data = try editingReader() }
        catch { throw Failure.unavailable }
        guard let data else { return WidgetCatalog() }
        guard let current = WidgetCatalog.decode(data) else { throw Failure.unavailable }
        return current
    }
}

extension ShortcutLaunchQueue {
    /// An unavailable library is not a verified empty or usable saved library.
    public func takeNextWidget(isActive: Bool, isReady: Bool, catalog: ShortcutCatalog,
                               verifiedAvailableIDs: Set<UUID>?) -> Request? {
        takeNext(isActive: isActive, isReady: isReady && verifiedAvailableIDs != nil,
                 catalog: catalog, availableIDs: verifiedAvailableIDs ?? [])
    }
}
