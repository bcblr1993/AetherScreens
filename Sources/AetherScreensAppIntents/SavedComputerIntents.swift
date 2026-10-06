import AppIntents
import Foundation
import AetherScreensCore

struct SavedComputerEntity: AppEntity {
    let id: UUID
    let alias: String
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Computer" }
    static var defaultQuery: SavedComputerQuery { SavedComputerQuery() }
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(alias)", image: .init(systemName: "display"))
    }
}

struct SavedComputerQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [SavedComputerEntity] {
        let entries = ShortcutCatalogReader.standard().read().entries
        return identifiers.compactMap { id in
            entries.first(where: { $0.id == id }).map { SavedComputerEntity(id: $0.id, alias: $0.alias) }
        }
    }

    func entities(matching string: String) async throws -> [SavedComputerEntity] {
        ShortcutCatalogReader.standard().read().entries
            .filter { $0.alias.localizedStandardContains(string) }
            .map { SavedComputerEntity(id: $0.id, alias: $0.alias) }
    }

    func suggestedEntities() async throws -> [SavedComputerEntity] {
        ShortcutCatalogReader.standard().read().entries
            .map { SavedComputerEntity(id: $0.id, alias: $0.alias) }
    }
}

struct OpenSavedComputerIntent: OpenIntent {
    static var title: LocalizedStringResource { "Open Computer" }
    static var description: IntentDescription { "Open a saved computer that you enabled in AetherScreens." }
    static var openAppWhenRun: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    @Parameter(title: "Computer") var target: SavedComputerEntity
    static var parameterSummary: some ParameterSummary { Summary("Open \(\.$target)") }
    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try ShortcutLaunchQueue.shared.enqueue(deviceID: target.id, catalog: ShortcutCatalogReader.standard().read())
        #if os(macOS)
        ShortcutLibraryWindowBridge.request()
        #endif
        return .result(dialog: "Open request submitted. Return to the library if a session or editor is already open.")
    }
}
