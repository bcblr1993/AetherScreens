import SwiftUI

/// Real-time diagnostic log inspector for troubleshooting network, RFB handshake, and authentication.
public struct DiagnosticLogView: View {
    @ObservedObject private var logger = AppLogger.shared
    @Environment(\.dismiss) private var dismiss

    @State private var filterText: String = ""
    @State private var selectedLevel: AppLogger.LogLevel? = nil
    @State private var copiedNotice: Bool = false

    public init() {}

    public var filteredEntries: [AppLogger.LogEntry] {
        logger.entries.filter { entry in
            let matchesLevel = selectedLevel == nil || entry.level == selectedLevel
            let matchesText = filterText.isEmpty ||
                entry.message.localizedCaseInsensitiveContains(filterText) ||
                entry.category.localizedCaseInsensitiveContains(filterText)
            return matchesLevel && matchesText
        }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter and Search Bar
                HStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Filter logs...", text: $filterText)
                            .textFieldStyle(.plain)
                        if !filterText.isEmpty {
                            Button {
                                filterText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(8)

                    Picker("Level", selection: $selectedLevel) {
                        Text("All Levels").tag(AppLogger.LogLevel?.none)
                        ForEach(AppLogger.LogLevel.allCases, id: \.self) { level in
                            Text(level.rawValue).tag(AppLogger.LogLevel?.some(level))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.03))

                Divider()

                // Log Output Terminal Window
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            if filteredEntries.isEmpty {
                                Text("No log entries match the current filter.")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.65))
                                    .padding(20)
                            } else {
                                ForEach(filteredEntries) { entry in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(entry.formattedTime)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.55))

                                        Text("[\(entry.category)]")
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundColor(.accentColor)

                                        Text(entry.message)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(colorForLevel(entry.level))
                                            .textSelection(.enabled)
                                    }
                                    .id(entry.id)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .background(Color(red: 0.08, green: 0.08, blue: 0.1))
                    .onChange(of: logger.entries.count) { _, _ in
                        if let lastId = filteredEntries.last?.id {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }

                Divider()

                // Bottom Action Toolbar
                HStack {
                    Text("\(filteredEntries.count) events")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    Spacer()

                    if copiedNotice {
                        Text("Copied to Clipboard!")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.green)
                            .transition(.opacity)
                    }

                    Button {
                        copyLogsToClipboard()
                    } label: {
                        Label("Copy Logs", systemImage: "doc.on.doc")
                    }

                    Button(role: .destructive) {
                        logger.clear()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.04))
            }
            .navigationTitle("Diagnostic Logs")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 450)
        #endif
    }

    private func colorForLevel(_ level: AppLogger.LogLevel) -> Color {
        switch level {
        case .debug: return .gray
        case .info: return .white
        case .warning: return .yellow
        case .error: return Color(red: 1.0, green: 0.4, blue: 0.4)
        }
    }

    private func copyLogsToClipboard() {
        let text = logger.exportLogs()
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif

        withAnimation {
            copiedNotice = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copiedNotice = false
            }
        }
    }
}
