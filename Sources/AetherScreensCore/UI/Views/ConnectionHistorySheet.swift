import SwiftUI

/// Sheet displaying recent connection sessions, durations, protocols, and outcomes.
public struct ConnectionHistorySheet: View {
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    @ObservedObject private var store: ConnectionHistoryStore
    @Environment(\.dismiss) private var dismiss
    public let filterDevice: RemoteDevice?

    @MainActor
    public init(store: ConnectionHistoryStore? = nil, filterDevice: RemoteDevice? = nil) {
        self.store = store ?? .shared
        self.filterDevice = filterDevice
    }

    private var displayedEntries: [ConnectionHistoryEntry] {
        if let filterDevice {
            return store.entries(for: filterDevice.id)
        }
        return store.entries
    }

    public var body: some View {
        NavigationStack {
            Group {
                if displayedEntries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(.secondary)
                        Text(AppLocalization.string("No connection history yet."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(displayedEntries) { entry in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(color(for: entry.outcome))
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(entry.deviceName)
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(entry.remoteProtocol.rawValue)
                                            .font(.system(size: 9, weight: .bold, design: .rounded))
                                            .foregroundStyle(entry.remoteProtocol == .rdp ? .blue : .teal)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1.5)
                                            .background((entry.remoteProtocol == .rdp ? Color.blue : Color.teal).opacity(0.12), in: Capsule())
                                    }
                                    Text("\(entry.host):\(entry.port)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(entry.startedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                    if let secs = entry.durationSeconds {
                                        Text(Self.formatDuration(secs))
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundStyle(.primary)
                                    } else {
                                        Text(AppLocalization.string(entry.outcome.rawValue))
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle(
                filterDevice.map { "\(AppLocalization.string("Connection History")) — \($0.name)" }
                    ?? AppLocalization.string("Connection History")
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !store.entries.isEmpty {
                        Button(AppLocalization.string("Clear History"), role: .destructive) {
                            store.clearAll()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("Done")) {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 400)
        #endif
    }

    private func color(for outcome: ConnectionHistoryEntry.Outcome) -> Color {
        switch outcome {
        case .active: return .blue
        case .completed: return .green
        case .failed: return .orange
        }
    }

    private static func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%dh %02dm %02ds", h, m, s)
        } else if m > 0 {
            return String(format: "%dm %02ds", m, s)
        } else {
            return "\(s)s"
        }
    }
}
