import Foundation

extension SessionViewModel {
    var canStartFileDownload: Bool {
        isForegroundSession && !isObserveOnly && client.fileCopyTransportGeneration != nil
            && !fileDownloadCoordinator.isBusy
    }

    func beginFileDownload(remotePath: String, destination: URL, onStarted: () -> Void) {
        guard canStartFileDownload else { return }
        let path = Data(remotePath.utf8)
        guard !path.isEmpty, path.count < 200, !path.contains(0),
              remotePath.hasPrefix("/") || remotePath.hasPrefix("~/") else {
            fileDownloadNotice = AppLocalization.string("Enter an absolute remote path or a path starting with ~/.")
            return
        }
        let access = FileTransferScopedAccess(destination)
        var handedOff = false
        defer { if !handedOff { access.close() } }
        do {
            let request = try AppleFileCopyStart(direction: .serverSends, flags: 1,
                reserved: Data(repeating: 0, count: 4), path: path,
                trailingBytes: Data()).message(sessionID: UInt32.random(in: 1...UInt32.max))
            handedOff = try fileDownloadCoordinator.start(filename: (remotePath as NSString).lastPathComponent,
                request: request, destination: destination, onReleased: { [weak self] in self?.objectWillChange.send() },
                onStopped: { access.close() })
            if handedOff { fileDownloadNotice = nil; onStarted() }
            else { fileDownloadNotice = AppLocalization.string("Cannot start file transfer on this connection.") }
        } catch {
            fileDownloadNotice = AppLocalization.string("Could not start download. Check the remote path and destination access.")
        }
    }
}
