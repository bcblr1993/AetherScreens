import Foundation
import SwiftUI
import WidgetKit
import AetherScreensWidgetSupport

struct SavedComputerWidgetEntry: TimelineEntry {
    enum State: Equatable {
        case placeholder
        case unconfigured
        case unavailable
        case ready
    }

    let date: Date
    let state: State
    let computerID: UUID?
    let alias: String?
}

struct SavedComputerWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SavedComputerWidgetEntry {
        SavedComputerWidgetEntry(date: Date(), state: .placeholder, computerID: nil, alias: nil)
    }

    func snapshot(for configuration: SavedComputerWidgetIntent, in context: Context) async -> SavedComputerWidgetEntry {
        freshEntry(for: configuration)
    }

    func timeline(for configuration: SavedComputerWidgetIntent, in context: Context) async -> Timeline<SavedComputerWidgetEntry> {
        Timeline(entries: [freshEntry(for: configuration)], policy: .never)
    }

    private func freshEntry(for configuration: SavedComputerWidgetIntent) -> SavedComputerWidgetEntry {
        guard let id = configuration.computer?.id else {
            return SavedComputerWidgetEntry(date: Date(), state: .unconfigured, computerID: nil, alias: nil)
        }
        // The system retains a configured entity. Only the current opt-in
        // projection may supply a title or make this entry open a computer.
        guard let entry = WidgetCatalogReader.standard().read().entries.first(where: { $0.id == id }) else {
            return SavedComputerWidgetEntry(date: Date(), state: .unavailable, computerID: nil, alias: nil)
        }
        return SavedComputerWidgetEntry(date: Date(), state: .ready, computerID: entry.id, alias: entry.alias)
    }
}

struct SavedComputerWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetSharedStorage.kind,
                               intent: SavedComputerWidgetIntent.self,
                               provider: SavedComputerWidgetProvider()) { entry in
            SavedComputerWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Connect")
        .description("Open one saved computer enabled in AetherScreens.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct SavedComputerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SavedComputerWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "display")
                .font(family == .systemSmall ? .title2 : .largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            title
                .font(.headline)
                .lineLimit(family == .systemSmall ? 2 : 3)
            subtitle
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(family == .systemSmall ? 3 : 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(launchURL)
    }

    @ViewBuilder
    private var title: some View {
        switch entry.state {
        case .placeholder:
            Text("Computer")
        case .unconfigured:
            Text("Choose a Computer")
        case .unavailable:
            Text("Computer Unavailable")
        case .ready:
            Text(verbatim: entry.alias ?? "")
                .privacySensitive()
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        switch entry.state {
        case .placeholder, .ready:
            Text("Open in AetherScreens")
        case .unconfigured:
            Text("Enable Show in Widgets in the computer's settings, then edit this widget.")
        case .unavailable:
            Text("Enable Show in Widgets for this computer in AetherScreens.")
        }
    }

    private var launchURL: URL? {
        if entry.state == .placeholder { return nil }
        if entry.state == .ready, let id = entry.computerID {
            return WidgetLaunchURL.url(for: id)
        }
        return WidgetLaunchURL.libraryURL
    }
}
