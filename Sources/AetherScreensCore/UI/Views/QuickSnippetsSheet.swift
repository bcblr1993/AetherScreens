import SwiftUI

/// Sheet for creating, editing, reordering, and sending reusable Quick Snippets.
public struct QuickSnippetsSheet: View {
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    @ObservedObject public var store: QuickSnippetStore
    public var onSendSnippet: ((QuickSnippet) -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var newTitle: String = ""
    @State private var newContent: String = ""
    @State private var newAppendReturn: Bool = true
    @State private var editingSnippet: QuickSnippet?

    @MainActor
    public init(store: QuickSnippetStore? = nil, onSendSnippet: ((QuickSnippet) -> Void)? = nil) {
        self.store = store ?? .shared
        self.onSendSnippet = onSendSnippet
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(AppLocalization.string(editingSnippet == nil ? "New Quick Snippet" : "Edit Quick Snippet"))) {
                    TextField(AppLocalization.string("Snippet Title (e.g. Restart Nginx)"), text: $newTitle)
                    TextField(AppLocalization.string("Command or Text Content"), text: $newContent)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                    Toggle(AppLocalization.string("Append Return (⏎) After Sending"), isOn: $newAppendReturn)

                    HStack {
                        if editingSnippet != nil {
                            Button(AppLocalization.string("Cancel")) {
                                clearForm()
                            }
                            .buttonStyle(.bordered)
                        }
                        Spacer()
                        Button(AppLocalization.string(editingSnippet == nil ? "Add Snippet" : "Save")) {
                            saveForm()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newContent.isEmpty)
                    }
                }

                Section(header: Text(AppLocalization.string("Saved Snippets"))) {
                    if store.snippets.isEmpty {
                        Text(AppLocalization.string("No saved snippets yet"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.snippets) { snippet in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(snippet.title)
                                            .font(.subheadline.weight(.semibold))
                                        if snippet.appendReturn {
                                            Text("⏎")
                                                .font(.caption2.weight(.bold))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                                        }
                                    }
                                    Text(snippet.content)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if let onSendSnippet {
                                    Button {
                                        onSendSnippet(snippet)
                                        dismiss()
                                    } label: {
                                        Image(systemName: "paperplane.fill")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help(AppLocalization.string("Send"))
                                    .accessibilityLabel(AppLocalization.string("Send"))
                                }
                                Button {
                                    editingSnippet = snippet
                                    newTitle = snippet.title
                                    newContent = snippet.content
                                    newAppendReturn = snippet.appendReturn
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.borderless)
                                .help(AppLocalization.string("Edit"))
                                .accessibilityLabel(AppLocalization.string("Edit"))

                                Button(role: .destructive) {
                                    if editingSnippet?.id == snippet.id { clearForm() }
                                    store.remove(id: snippet.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help(AppLocalization.string("Delete"))
                                .accessibilityLabel(AppLocalization.string("Delete"))
                            }
                            .padding(.vertical, 2)
                        }
                        .onMove { source, destination in
                            store.move(fromOffsets: source, toOffset: destination)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(AppLocalization.string("Quick Snippets"))
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(AppLocalization.string("Reset Defaults")) {
                        clearForm()
                        store.resetToDefaults()
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
        .frame(width: 520, height: 500)
        #endif
    }

    private func saveForm() {
        let trimmedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !newContent.isEmpty else { return }
        if let editing = editingSnippet {
            store.update(QuickSnippet(id: editing.id, title: trimmedTitle, content: newContent, appendReturn: newAppendReturn))
        } else {
            store.add(QuickSnippet(title: trimmedTitle, content: newContent, appendReturn: newAppendReturn))
        }
        clearForm()
    }

    private func clearForm() {
        editingSnippet = nil
        newTitle = ""
        newContent = ""
        newAppendReturn = true
    }
}
