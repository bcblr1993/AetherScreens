import SwiftUI
import UniformTypeIdentifiers

struct FileDownloadSheet: View {
    @ObservedObject var viewModel: SessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var remotePath = ""
    @State private var destination: URL?
    @State private var selectingFolder = false
    @FocusState private var pathFocused: Bool

    init(viewModel: SessionViewModel) {
        self.viewModel = viewModel
        let defaultDest = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        _destination = State(initialValue: defaultDest)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(AppLocalization.string("Receive File or Folder")).font(.title2.bold())
                Text(viewModel.device.name).font(.subheadline).foregroundStyle(.secondary)
                TextField(AppLocalization.string("Remote File or Folder"), text: $remotePath)
                    .textFieldStyle(.roundedBorder)
                    .focused($pathFocused)
                    #if canImport(UIKit)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    #endif
                    .onSubmit { pathFocused = false }
                    .accessibilityIdentifier("file-download-source")

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(AppLocalization.string("Quick Path Prefixes"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        let recents = FileTransferHistoryStore.shared.recentDownloadPaths
                        if !recents.isEmpty {
                            Menu {
                                ForEach(recents, id: \.self) { recent in
                                    Button(recent) {
                                        remotePath = recent
                                        pathFocused = false
                                    }
                                }
                            } label: {
                                Label(AppLocalization.string("Recent"), systemImage: "clock")
                                    .font(.caption)
                            }
                            .menuStyle(.borderlessButton)
                            .accessibilityIdentifier("file-download-recent-menu")
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(FileTransferPresetLocation.standardPresets) { preset in
                                Button {
                                    remotePath = preset.path.hasSuffix("/") ? preset.path : "\(preset.path)/"
                                    pathFocused = true
                                } label: {
                                    Label(AppLocalization.string(preset.titleKey), systemImage: preset.systemIcon)
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .tint(remotePath.hasPrefix(preset.path) ? .blue : .secondary)
                                .accessibilityIdentifier("file-download-preset-\(preset.id)")
                            }
                        }
                    }
                }

                folderPickerCard
                Text(AppLocalization.string("Choose an existing local folder. Existing files are never replaced; choose another folder if a name already exists."))
                    .font(.caption).foregroundStyle(.secondary)
                Text(AppLocalization.string("Up to 1 GB and 1,024 items per transfer. Symbolic links are not supported."))
                    .font(.caption).foregroundStyle(.secondary)
                if let notice = viewModel.fileDownloadNotice {
                    Text(notice).font(.callout).foregroundStyle(.red)
                        .accessibilityIdentifier("file-download-error")
                }
            }
            .padding(24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack { Spacer(minLength: 0); cancelButton; receiveButton }
                VStack(alignment: .trailing) { receiveButton; cancelButton }
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            .background(.regularMaterial)
        }
        #if os(macOS)
        .frame(width: 440, height: 400)
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
        .fileImporter(isPresented: $selectingFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): destination = urls.first; viewModel.fileDownloadNotice = nil
            case .failure: viewModel.fileDownloadNotice = AppLocalization.string("Could not open the file picker.")
            }
        }
    }
    private var cancelButton: some View {
        Button { dismiss() } label: { actionTitle("Cancel") }
            .buttonStyle(.bordered).keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("file-download-cancel")
    }
    private var receiveButton: some View {
        Button {
            guard let destination else { return }
            pathFocused = false
            FileTransferHistoryStore.shared.recordDownloadPath(remotePath)
            viewModel.beginFileDownload(remotePath: remotePath, destination: destination) { dismiss() }
        } label: { actionTitle("Receive") }
        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("file-download-start")
        .disabled(destination == nil || remotePath.isEmpty || !viewModel.canStartFileDownload)
    }
    @ViewBuilder
    private func actionTitle(_ key: String) -> some View {
        Text(AppLocalization.string(key))
            .fixedSize(horizontal: true, vertical: false)
            #if canImport(UIKit)
            .frame(minWidth: 64, minHeight: 44)
            #endif
    }

    private var folderPickerCard: some View {
        Button { selectingFolder = true } label: {
            HStack(spacing: 12) {
                folderIcon
                folderTextContent
                Spacer()
                if destination != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(folderCardBackground)
            .overlay(folderCardBorder)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("file-download-select")
    }

    private var folderIcon: some View {
        let hasFolder = destination != nil
        return Image(systemName: "folder.fill")
            .font(.title2)
            .foregroundStyle(hasFolder ? Color.blue : Color.secondary)
    }

    private var folderTextContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(destination?.lastPathComponent ?? AppLocalization.string("Choose Save Folder"))
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(destination?.path ?? AppLocalization.string("Select destination on local device"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var folderCardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.secondary.opacity(0.08))
    }

    private var folderCardBorder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
    }
}
