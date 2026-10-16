import SwiftUI
import UniformTypeIdentifiers

struct FileUploadSheet: View {
    @ObservedObject var viewModel: SessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectingFile = false
    @State private var selectedURL: URL?
    @State private var destination = "~/Desktop"
    @FocusState private var destinationFocused: Bool
    @State private var isTargetedForDrop = false

    init(viewModel: SessionViewModel, initialURL: URL? = nil) {
        self.viewModel = viewModel
        _selectedURL = State(initialValue: initialURL)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(AppLocalization.string("Send File or Folder"))
                    .font(.title2.bold())
                Text(viewModel.device.name).font(.subheadline).foregroundStyle(.secondary)
                filePickerCard
                TextField(AppLocalization.string("Remote Folder"), text: $destination)
                    .textFieldStyle(.roundedBorder)
                    .focused($destinationFocused)
                    #if canImport(UIKit)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    #endif
                    .onSubmit { destinationFocused = false }
                    .accessibilityIdentifier("file-upload-destination")
                    .disabled(viewModel.isPreparingFileUpload)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(AppLocalization.string("Common Locations"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        let recents = FileTransferHistoryStore.shared.recentUploadDestinations
                        if !recents.isEmpty {
                            Menu {
                                ForEach(recents, id: \.self) { recent in
                                    Button(recent) { destination = recent }
                                }
                            } label: {
                                Label(AppLocalization.string("Recent"), systemImage: "clock")
                                    .font(.caption)
                            }
                            .menuStyle(.borderlessButton)
                            .accessibilityIdentifier("file-upload-recent-menu")
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(FileTransferPresetLocation.standardPresets) { preset in
                                Button {
                                    destination = preset.path
                                } label: {
                                    Label(AppLocalization.string(preset.titleKey), systemImage: preset.systemIcon)
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .tint(destination == preset.path ? .blue : .secondary)
                                .accessibilityIdentifier("file-upload-preset-\(preset.id)")
                            }
                        }
                    }
                }

                Text(AppLocalization.string("Use an existing remote folder. Same-name files may be saved under a new name. Stopping may leave partial files."))
                    .font(.caption).foregroundStyle(.secondary)
                Text(AppLocalization.string("Up to 1 GB and 1,024 items per transfer. Symbolic links are not supported."))
                    .font(.caption).foregroundStyle(.secondary)
                if viewModel.isPreparingFileUpload {
                    ProgressView(AppLocalization.string("Preparing Files…"))
                }
                if let notice = viewModel.fileUploadNotice {
                    Text(notice).font(.callout).foregroundStyle(.red)
                        .accessibilityIdentifier("file-upload-error")
                }
            }
            .padding(24)
            .frame(maxWidth: 440, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionBar
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.regularMaterial)
        }
        #if os(macOS)
        .frame(width: 440, height: 460)
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
        .interactiveDismissDisabled(viewModel.isPreparingFileUpload)
        .fileImporter(isPresented: $selectingFile, allowedContentTypes: [.item, .folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): selectedURL = urls.first; viewModel.fileUploadNotice = nil
            case .failure: viewModel.fileUploadNotice = AppLocalization.string("Could not open the file picker.")
            }
        }
        .dropDestination(for: URL.self, action: { urls, _ in
            guard let url = urls.first, url.isFileURL else { return false }
            selectedURL = url
            viewModel.fileUploadNotice = nil
            return true
        }, isTargeted: { targeted in
            isTargetedForDrop = targeted
        })
    }

    private var actionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Spacer(minLength: 0)
                cancelButton
                sendButton
            }
            VStack(alignment: .trailing, spacing: 8) {
                sendButton
                cancelButton
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var cancelButton: some View {
        Button {
            if viewModel.isPreparingFileUpload { viewModel.stopFileTransfers() }
            dismiss()
        } label: {
            actionTitle("Cancel")
        }
        .buttonStyle(.bordered)
        .keyboardShortcut(.cancelAction)
        .accessibilityIdentifier("file-upload-cancel")
    }

    private var sendButton: some View {
        Button {
            guard let selectedURL else { return }
            destinationFocused = false
            FileTransferHistoryStore.shared.recordUploadDestination(destination)
            viewModel.beginFileUpload(url: selectedURL, destination: destination) { dismiss() }
        } label: {
            actionTitle("Send")
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("file-upload-send")
        .disabled(selectedURL == nil || !viewModel.canStartFileUpload)
    }

    @ViewBuilder
    private func actionTitle(_ key: String) -> some View {
        #if canImport(UIKit)
        Text(AppLocalization.string(key))
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 64, minHeight: 44)
        #else
        Text(AppLocalization.string(key))
            .fixedSize(horizontal: true, vertical: false)
        #endif
    }

    private var filePickerCard: some View {
        Button { selectingFile = true } label: {
            HStack(spacing: 12) {
                fileIcon
                fileTextContent
                Spacer()
                if selectedURL != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .overlay(cardBorder)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isPreparingFileUpload)
        .accessibilityIdentifier("file-upload-select")
    }

    private var fileIcon: some View {
        let hasFile = selectedURL != nil
        return Image(systemName: hasFile ? "doc.fill" : "doc.badge.plus")
            .font(.title2)
            .foregroundStyle(hasFile ? Color.blue : Color.secondary)
    }

    private var fileTextContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(selectedURL?.lastPathComponent ?? AppLocalization.string("Choose File or Folder"))
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(selectedURL != nil ? AppLocalization.string("Click to choose another file") : AppLocalization.string("Drop files here or click to browse"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isTargetedForDrop ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.08))
    }

    private var cardBorder: some View {
        let dashPattern: [CGFloat] = selectedURL == nil ? [6, 4] : []
        let strokeColor: Color = isTargetedForDrop ? .blue : .secondary.opacity(0.2)
        let strokeWidth: CGFloat = isTargetedForDrop ? 2 : 1
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(strokeColor, style: StrokeStyle(lineWidth: strokeWidth, dash: dashPattern))
    }
}
