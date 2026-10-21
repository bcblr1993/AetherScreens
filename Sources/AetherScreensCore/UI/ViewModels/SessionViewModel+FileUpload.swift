import Foundation
import RDPKit

extension SessionViewModel {
    func stopFileTransfers() {
        fileUploadPreparationID = UUID()
        fileUploadPreparationTask?.cancel()
        fileUploadPreparationTask = nil
        isPreparingFileUpload = false
        fileTransfers.cancelAll()
    }

    var canStartFileUpload: Bool {
        if isRDP {
            return isForegroundSession && !isObserveOnly && rdpClient != nil && sessionState == .connected
        }
        return isForegroundSession && !isObserveOnly && client.fileCopyTransportGeneration != nil
            && !isPreparingFileUpload && !fileUploadCoordinator.isBusy
    }

    public func transferDroppedFilesToRDP(urls: [URL]) {
        guard isRDP, let rdp = rdpClient else { return }

        var localFiles: [RDPClipboardLocalFile] = []
        var transferredNames: [String] = []

        for url in urls {
            guard url.isFileURL else { continue }
            let fileName = url.lastPathComponent
            do {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                localFiles.append(RDPClipboardLocalFile(fileName: fileName, contents: data))
                transferredNames.append(fileName)
            } catch {
                AppLogger.shared.error("Failed to read file \(fileName) for RDP transfer: \(error)", category: "RDP")
            }
        }

        guard !localFiles.isEmpty else { return }

        let success = rdp.publishLocalFiles(localFiles)
        if success {
            let namesString = transferredNames.joined(separator: ", ")
            for name in transferredNames {
                FileTransferHistoryStore.shared.recordUploadDestination("Windows Desktop (\(name))")
            }

            let msg = String(format: AppLocalization.string("File \"%@\" copied to Windows clipboard. Press Ctrl+V in Windows to paste."), namesString)
            self.fileUploadNotice = msg

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, self.isRDP, self.sessionState == .connected else { return }
                self.sendCommandShortcut("v")
            }
        } else {
            self.fileUploadNotice = AppLocalization.string("Cannot start file transfer on this connection.")
        }
    }

    func beginFileUpload(url: URL, destination: String, onStarted: @escaping () -> Void) {
        let path = Data(destination.utf8)
        guard !path.isEmpty, path.count < 200, !path.contains(0),
              destination.hasPrefix("/") || destination.hasPrefix("~/") else {
            fileUploadNotice = AppLocalization.string("Enter an absolute remote folder or a path starting with ~/.")
            return
        }
        FileTransferHistoryStore.shared.recordUploadDestination(destination)
        guard canStartFileUpload, let generation = client.fileCopyTransportGeneration else { return }
        let identity = UUID()
        fileUploadPreparationID = identity
        isPreparingFileUpload = true
        fileUploadNotice = nil
        let access = FileTransferScopedAccess(url)
        fileUploadPreparationTask = Task { [weak self] in
            var handedOff = false
            defer {
                if !handedOff { access.close() }
                if let self, self.fileUploadPreparationID == identity {
                    self.isPreparingFileUpload = false
                    self.fileUploadPreparationTask = nil
                }
            }
            do {
                let preparation = Task.detached(priority: .utility) {
                    try AppleFileCopyUploadSnapshot.prepare(url: url, isCancelled: { Task.isCancelled })
                }
                let snapshot = try await withTaskCancellationHandler(operation: {
                    try await preparation.value
                }, onCancel: { preparation.cancel() })
                defer { if !handedOff { snapshot.removeInBackground() } }
                let prepared = snapshot.prepared
                try Task.checkCancellation()
                guard let self, self.fileUploadPreparationID == identity,
                      self.client.fileCopyTransportGeneration == generation,
                      self.isForegroundSession, !self.isObserveOnly else { return }
                let sessionID = UInt32.random(in: 1...UInt32.max)
                let start = try AppleFileCopyStart(direction: .serverReceives, flags: 0,
                    reserved: Data(repeating: 0, count: 4), path: path,
                    trailingBytes: Data()).message(sessionID: sessionID)
                let totals = try AppleFileCopyItemInfo(rawHeaderValue: 0, reserved: Data(repeating: 0, count: 4),
                    logicalBytes: prepared.logicalBytes, physicalBytes: prepared.physicalBytes, fileCount: prepared.fileCount,
                    forkCount: prepared.forkCount, folderCount: prepared.folderCount,
                    allocationSize: 4096, trailing: Data()).message(sessionID: sessionID)
                let job = FileTransferJob(direction: .upload, filename: url.lastPathComponent, totalBytes: prepared.logicalBytes)
                handedOff = try self.fileUploadCoordinator.start(job: job, sources: prepared.sources,
                    start: start, totals: totals, onReleased: { [weak self] in snapshot.removeInBackground(); access.close(); self?.objectWillChange.send() })
                if handedOff { onStarted() }
                else { self.fileUploadNotice = AppLocalization.string("Cannot start file transfer on this connection.") }
            } catch AppleFileCopyDiskSpace.Failure.insufficientSpace {
                guard !Task.isCancelled, let self, self.fileUploadPreparationID == identity else { return }
                self.fileUploadNotice = AppLocalization.string("Not enough temporary storage to prepare this upload. Free space and try again.")
            } catch {
                guard !Task.isCancelled, let self, self.fileUploadPreparationID == identity else { return }
                self.fileUploadNotice = AppLocalization.string("Could not prepare the selected file or folder. Check access and transfer limits.")
            }
        }
    }
}

@MainActor
final class FileTransferScopedAccess {
    private let url: URL
    private var opened: Bool
    init(_ url: URL) { self.url = url; opened = url.startAccessingSecurityScopedResource() }
    func close() { if opened { opened = false; url.stopAccessingSecurityScopedResource() } }
}
