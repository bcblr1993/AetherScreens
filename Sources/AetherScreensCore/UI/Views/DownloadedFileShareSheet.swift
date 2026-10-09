#if canImport(UIKit)
import SwiftUI
import UIKit

/// Present from a view in the current scene; keep access until activity dismissal.
struct DownloadedFileShareSheet: UIViewControllerRepresentable {
    let saved: FileTransferTaskStore.SavedFile
    let onFinished: @MainActor () -> Void

    func makeUIViewController(context: Context) -> DownloadSharePresenter {
        DownloadSharePresenter(saved: saved, onFinished: onFinished)
    }
    func updateUIViewController(_ controller: DownloadSharePresenter, context: Context) {}
    static func dismantleUIViewController(_ controller: DownloadSharePresenter, coordinator: ()) {
        controller.stop()
    }
}

final class DownloadSharePresenter: UIViewController, UIPopoverPresentationControllerDelegate, UIAdaptivePresentationControllerDelegate {
    private let saved: FileTransferTaskStore.SavedFile
    private let access: FileTransferScopedAccess
    private let onFinished: @MainActor () -> Void
    private var started = false
    private var finished = false

    init(saved: FileTransferTaskStore.SavedFile, onFinished: @escaping @MainActor () -> Void) {
        self.saved = saved
        self.access = FileTransferScopedAccess(saved.accessRoot)
        self.onFinished = onFinished
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); presentIfReady() }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); presentIfReady() }

    private func presentIfReady() {
        guard !started, !finished, view.window != nil, !view.bounds.isEmpty else { return }
        started = true
        let activity = UIActivityViewController(activityItems: [saved.url], applicationActivities: nil)
        if traitCollection.userInterfaceIdiom == .pad {
            activity.modalPresentationStyle = .popover
            activity.popoverPresentationController?.sourceView = view
            activity.popoverPresentationController?.sourceRect = view.bounds
            activity.popoverPresentationController?.delegate = self
        }
        activity.presentationController?.delegate = self
        activity.completionWithItemsHandler = { [weak self] _, _, _, _ in
            Task { @MainActor [weak self] in self?.finish() }
        }
        present(activity, animated: true) { [weak self, weak activity] in
            activity?.presentationController?.delegate = self
        }
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { finish() }
    func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) { finish() }
    private func finish() {
        guard !finished else { return }
        finished = true
        access.close()
        onFinished()
    }
    func stop() {
        presentedViewController?.dismiss(animated: false)
        finish()
    }
}
#endif
