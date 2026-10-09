import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Session task presentation. No task is created by rendering this view.
struct FileTransferProgressView: View {
    @ObservedObject var store: FileTransferTaskStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if canImport(UIKit)
    private struct ShareSelection: Identifiable {
        let id = UUID()
        let jobID: UUID
        let saved: FileTransferTaskStore.SavedFile
    }
    @State private var shareSelection: ShareSelection?
    #endif

    var body: some View {
        if !store.jobs.isEmpty {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(visibleJobs) { job in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Image(systemName: job.direction == .upload ? "arrow.up.doc" : "arrow.down.doc")
                                    Text(store.displayFilename(for: job)).lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 8)
                                    if active(job) {
                                        Button { _ = store.cancel(job.id) } label: { transferAction("xmark.circle") }
                                            .accessibilityLabel(AppLocalization.string("Cancel transfer"))
                                            .accessibilityIdentifier("file-transfer-cancel-\(job.id)")
                                    } else {
                                        Button { store.dismiss(job.id) } label: { transferAction("xmark") }
                                            .accessibilityLabel(AppLocalization.string("Dismiss"))
                                            .accessibilityIdentifier("file-transfer-dismiss-\(job.id)")
                                    }
                                }
                                .buttonStyle(.plain)
                                if active(job) {
                                    if !job.isSizeKnown || job.transferredBytes == 0 { ProgressView() }
                                    else { ProgressView(value: job.fractionCompleted) }
                                }
                                Text(status(job)).font(.caption).foregroundStyle(.secondary)
                                #if canImport(AppKit)
                                if let saved = store.savedFile(for: job.id) {
                                    Button {
                                        let opened = saved.accessRoot.startAccessingSecurityScopedResource()
                                        defer { if opened { saved.accessRoot.stopAccessingSecurityScopedResource() } }
                                        NSWorkspace.shared.activateFileViewerSelecting([saved.url])
                                    } label: {
                                        Label(AppLocalization.string("Show in Finder"), systemImage: "folder")
                                    }
                                    .font(.caption)
                                    .accessibilityIdentifier("file-transfer-reveal-\(job.id)")
                                }
                                #elseif canImport(UIKit)
                                if let saved = store.savedFile(for: job.id) {
                                    Button {
                                        guard shareSelection == nil else { return }
                                        shareSelection = .init(jobID: job.id, saved: saved)
                                    } label: {
                                        Label(AppLocalization.string("Share"), systemImage: "square.and.arrow.up")
                                            .frame(minHeight: 44)
                                    }
                                    .font(.caption)
                                    .disabled(shareSelection != nil)
                                    .accessibilityIdentifier("file-transfer-share-\(job.id)")
                                    .background {
                                        if let selection = shareSelection, selection.jobID == job.id {
                                            DownloadedFileShareSheet(saved: selection.saved) {
                                                Task { @MainActor in
                                                    if shareSelection?.id == selection.id { shareSelection = nil }
                                                }
                                            }
                                            .frame(width: 1, height: 1)
                                            .accessibilityHidden(true)
                                        }
                                    }
                                }
                                #endif
                                Text(byteProgress(job))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("file-transfer-bytes-\(job.id)")
                            }
                            .id(job.id)
                            .transition(.opacity)
                        }
                    }
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: visibleJobs.map(\.id))
                    .padding(12)
                }
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: visibleJobs.first(where: { active($0) })?.id, initial: true) { _, id in
                    guard let id else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                        proxy.scrollTo(id, anchor: .top)
                    }
                }
                .frame(maxWidth: 320, maxHeight: 240)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))

            }
        }
    }

    private var visibleJobs: [FileTransferJob] {
        let newest = store.jobs.reversed()
        return newest.filter { active($0) } + newest.filter { !active($0) }
    }

    private func byteProgress(_ job: FileTransferJob) -> String {
        let transferred = ByteCountFormatter.string(fromByteCount: Int64(clamping: job.transferredBytes), countStyle: .file)
        guard job.isSizeKnown else { return transferred }
        let total = ByteCountFormatter.string(fromByteCount: Int64(clamping: job.totalBytes), countStyle: .file)
        return "\(transferred) / \(total)"
    }

    private func transferAction(_ symbol: String) -> some View {
        Image(systemName: symbol)
            #if canImport(UIKit)
            .frame(width: 44, height: 44)
            #else
            .frame(width: 24, height: 24)
            #endif
            .contentShape(Rectangle())
    }

    private func active(_ job: FileTransferJob) -> Bool {
        switch job.state {
        case .queued, .awaitingOverwriteDecision, .transferring, .paused: true
        default: false
        }
    }

    private func status(_ job: FileTransferJob) -> String {
        switch job.state {
        case .completed: AppLocalization.string("Transfer complete")
        case .cancelled:
            AppLocalization.string(job.direction == .upload ? "Transfer stopped. Check the remote folder for partial files." : "Transfer stopped. Check the destination folder for saved files.")
        case .failed(let message): AppLocalization.string(message)
        case .paused: AppLocalization.string("Transfer paused")
        default: AppLocalization.string("Transferring")
        }
    }
}
