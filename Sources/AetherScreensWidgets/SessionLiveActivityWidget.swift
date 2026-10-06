#if os(iOS) && canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
import SwiftUI
import WidgetKit
import AetherScreensWidgetSupport

struct SessionLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: symbol(context))
                    .font(.title2)
                    .foregroundStyle(tint(context))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Remote Session").font(.headline)
                    Text(title(context)).font(.subheadline)
                    Text(detail(context)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding()
            .activityBackgroundTint(.black.opacity(0.12))
            .activitySystemActionForegroundColor(.primary)
            .widgetURL(WidgetLaunchURL.libraryURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: symbol(context)).foregroundStyle(tint(context))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(title(context)).font(.caption).foregroundStyle(tint(context))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Remote Session").font(.headline)
                        Text(detail(context)).font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "display").foregroundStyle(tint(context))
            } compactTrailing: {
                Image(systemName: symbol(context))
                    .foregroundStyle(tint(context))
                    .accessibilityLabel(Text(title(context)))
            } minimal: {
                Image(systemName: symbol(context))
                    .foregroundStyle(tint(context))
                    .accessibilityLabel(Text(title(context)))
            }
            .widgetURL(WidgetLaunchURL.libraryURL)
            .keylineTint(tint(context))
        }
    }

    private func title(_ context: ActivityViewContext<SessionActivityAttributes>) -> LocalizedStringKey {
        if context.isStale { return "Session Status Unavailable" }
        switch context.state.phase {
        case .connected: return "Connected in App"
        case .paused: return "Paused in Background"
        case .ended: return "Session Ended"
        case .failed: return "Connection Ended"
        }
    }

    private func detail(_ context: ActivityViewContext<SessionActivityAttributes>) -> LocalizedStringKey {
        if context.isStale { return "Open the app to check the connection." }
        switch context.state.phase {
        case .connected: return "Remote control runs while the app is in the foreground."
        case .paused: return "The connection was closed. Open the app to reconnect."
        case .ended, .failed: return "Open the app to start another session."
        }
    }

    private func symbol(_ context: ActivityViewContext<SessionActivityAttributes>) -> String {
        if context.isStale { return "questionmark.circle" }
        switch context.state.phase {
        case .connected: return "link"
        case .paused: return "pause.circle"
        case .ended: return "checkmark.circle"
        case .failed: return "exclamationmark.circle"
        }
    }

    private func tint(_ context: ActivityViewContext<SessionActivityAttributes>) -> Color {
        if context.isStale { return .gray }
        switch context.state.phase {
        case .connected: return .green
        case .paused: return .orange
        case .ended: return .secondary
        case .failed: return .red
        }
    }
}
#endif
