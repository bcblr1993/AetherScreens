import AppIntents
import Foundation

public struct SavedComputerEntity: AppEntity {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Computer"
    public static var defaultQuery = SavedComputerQuery()
    public let id: UUID
    public let name: String
    public let host: String
    public init(device: RemoteDevice) { id = device.id; name = device.name; host = device.host }
    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(host)")
    }
}

public struct SavedComputerQuery: EntityQuery {
    private let store: DeviceStore
    public init() { self.store = .shared }
    public init(store: DeviceStore) { self.store = store }
    @MainActor public func entities(for identifiers: [UUID]) async throws -> [SavedComputerEntity] {
        store.loadDevices()
        return identifiers.compactMap { id in store.devices.first { $0.id == id }.map(SavedComputerEntity.init) }
    }
    @MainActor public func suggestedEntities() async throws -> [SavedComputerEntity] {
        store.loadDevices()
        return store.devices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map(SavedComputerEntity.init)
    }
}

public struct ConnectSavedComputerIntent: AppIntent {
    public static var title: LocalizedStringResource = "Connect to Computer"
    public static var openAppWhenRun: Bool = true
    @Parameter(title: "Computer") public var computer: SavedComputerEntity
    public static var parameterSummary: some ParameterSummary { Summary("Connect to \(\.$computer)") }
    public init() {}
    @MainActor public func perform() async throws -> some IntentResult {
        DeviceStore.shared.loadDevices()
        guard DeviceStore.shared.devices.contains(where: { $0.id == computer.id }) else {
            throw SavedComputerIntentError.missingComputer
        }
        SavedComputerIntentInbox.shared.enqueue(computer.id)
        return .result()
    }
}

public struct AetherScreensCoreIntents: AppIntentsPackage { public init() {} }

public enum SavedComputerIntentError: LocalizedError {
    case missingComputer
    public var errorDescription: String? {
        AppLocalization.string(ConnectionLink.Failure.missingSavedComputer.messageKey)
    }
}
