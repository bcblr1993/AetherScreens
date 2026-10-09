import SwiftUI
import UniformTypeIdentifiers

struct FileUploadSheet: View {
    @ObservedObject var viewModel: SessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectingFile = false
    @State private var selectedURL: URL?
    @State private var destination = "~/Desktop"
    @FocusState private var destinationFocused: Bool

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
                Button { selectingFile = true } label: {
                    Label(selectedURL?.lastPathComponent ?? AppLocalization.string("Choose File or Folder"), systemImage: "doc.badge.arrow.up")
                        .lineLimit(1)
                }
                .disabled(viewModel.isPreparingFileUpload)
                .accessibilityIdentifier("file-upload-select")
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
}
