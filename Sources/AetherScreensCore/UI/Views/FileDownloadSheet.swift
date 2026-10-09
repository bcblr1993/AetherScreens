import SwiftUI
import UniformTypeIdentifiers

struct FileDownloadSheet: View {
    @ObservedObject var viewModel: SessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var remotePath = ""
    @State private var destination: URL?
    @State private var selectingFolder = false
    @FocusState private var pathFocused: Bool

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
                Button { selectingFolder = true } label: {
                    Label(destination?.lastPathComponent ?? AppLocalization.string("Choose Save Folder"), systemImage: "folder")
                        .lineLimit(1).truncationMode(.middle)
                }
                .accessibilityIdentifier("file-download-select")
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
}
