import AppIntents
import Foundation
import AetherScreensWidgetSupport

struct WidgetComputerEntity: AppEntity {
    let id: UUID
    let alias: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Computer" }
    static var defaultQuery: WidgetComputerQuery { WidgetComputerQuery() }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(alias)", image: .init(systemName: "display"))
    }
}

struct WidgetComputerQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [WidgetComputerEntity] {
        let entries = WidgetCatalogReader.standard().read().entries
        return identifiers.compactMap { id in
            entries.first(where: { $0.id == id }).map {
                WidgetComputerEntity(id: $0.id, alias: $0.alias)
            }
        }
    }

    func entities(matching string: String) async throws -> [WidgetComputerEntity] {
        WidgetCatalogReader.standard().read().entries
            .filter { $0.alias.localizedStandardContains(string) }
            .map { WidgetComputerEntity(id: $0.id, alias: $0.alias) }
    }

    func suggestedEntities() async throws -> [WidgetComputerEntity] {
        WidgetCatalogReader.standard().read().entries
            .map { WidgetComputerEntity(id: $0.id, alias: $0.alias) }
    }
}

struct SavedComputerWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Saved Computer" }
    static var description: IntentDescription {
        "Choose a computer that you enabled for Widgets in AetherScreens."
    }

    @Parameter(title: "Computer") var computer: WidgetComputerEntity?

    init() {}
}
