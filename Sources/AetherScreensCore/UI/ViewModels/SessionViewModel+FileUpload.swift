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

    func collectLocalFiles(from urls: [URL]) -> (files: [RDPClipboardLocalFile], names: [String]) {
        var localFiles: [RDPClipboardLocalFile] = []
        var transferredNames: [String] = []
        let fileManager = FileManager.default

        for rootURL in urls {
            guard rootURL.isFileURL else { continue }
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDir) else { continue }
            let rootName = rootURL.lastPathComponent
            transferredNames.append(rootName)

            if isDir.boolValue {
                let dirDescriptor = RDPClipboardFileDescriptorW(
                    flags: RDPClipboardFileDescriptorFlags.attributes | RDPClipboardFileDescriptorFlags.unicode,
                    fileAttributes: RDPClipboardFileAttributes.directory,
                    fileSize: 0,
                    fileName: rootName
                )
                localFiles.append(RDPClipboardLocalFile(descriptor: dirDescriptor, contents: Data()))

                if let enumerator = fileManager.enumerator(
                    at: rootURL,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                ) {
                    for case let itemURL as URL in enumerator {
                        guard let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]) else { continue }
                        guard let subComponents = Self.relativeComponents(of: itemURL, under: rootURL) else { continue }
                        let winRelativePath = ([rootName] + subComponents).joined(separator: "\\")
                        if resourceValues.isDirectory == true {
                            let subDirDesc = RDPClipboardFileDescriptorW(
                                flags: RDPClipboardFileDescriptorFlags.attributes | RDPClipboardFileDescriptorFlags.unicode,
                                fileAttributes: RDPClipboardFileAttributes.directory,
                                fileSize: 0,
                                fileName: winRelativePath
                            )
                            localFiles.append(RDPClipboardLocalFile(descriptor: subDirDesc, contents: Data()))
                        } else {
                            if let data = try? Data(contentsOf: itemURL, options: .mappedIfSafe) {
                                let fileDesc = RDPClipboardFileDescriptorW(
                                    flags: RDPClipboardFileDescriptorFlags.attributes | RDPClipboardFileDescriptorFlags.fileSize | RDPClipboardFileDescriptorFlags.unicode,
                                    fileAttributes: RDPClipboardFileAttributes.archive,
                                    fileSize: UInt64(data.count),
                                    fileName: winRelativePath
                                )
                                localFiles.append(RDPClipboardLocalFile(descriptor: fileDesc, contents: data))
                            }
                        }
                    }
                }
            } else {
                do {
                    let data = try Data(contentsOf: rootURL, options: .mappedIfSafe)
                    localFiles.append(RDPClipboardLocalFile(fileName: rootName, contents: data))
                } catch {
                    AppLogger.shared.error("Failed to read file \(rootName) for RDP transfer: \(error)", category: "RDP")
                }
            }
        }

        return (localFiles, transferredNames)
    }

    /// Enumerators may report /private/var while the root is /var, so compare resolved path components.
    nonisolated static func relativeComponents(of itemURL: URL, under rootURL: URL) -> [String]? {
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        // Resolve only the parent so a symlink inside the folder keeps its own name.
        let standardizedItem = itemURL.standardizedFileURL
        let item = standardizedItem.deletingLastPathComponent().resolvingSymlinksInPath().pathComponents
            + [standardizedItem.lastPathComponent]
        guard item.count > root.count, Array(item.prefix(root.count)) == root else { return nil }
        return Array(item.dropFirst(root.count))
    }

    @discardableResult
    func publishFilesToRDP(urls: [URL], notify: Bool = true) -> Bool {
        guard isRDP, let rdp = rdpClient else { return false }
        let (localFiles, transferredNames) = collectLocalFiles(from: urls)
        guard !localFiles.isEmpty else { return false }

        let success = rdp.publishLocalFiles(localFiles)
        if success && notify {
            let namesString = transferredNames.joined(separator: ", ")
            for name in transferredNames {
                FileTransferHistoryStore.shared.recordUploadDestination("Windows Desktop (\(name))")
            }
            let msg = String(format: AppLocalization.string("File \"%@\" copied to Windows clipboard. Press Ctrl+V in Windows to paste."), namesString)
            self.fileUploadNotice = msg
        }
        return success
    }

    public func transferDroppedFilesToRDP(urls: [URL], at dropPoint: CGPoint? = nil, in viewportSize: CGSize? = nil) {
        guard isRDP, let rdp = rdpClient else { return }

        guard publishFilesToRDP(urls: urls, notify: true) else {
            self.fileUploadNotice = AppLocalization.string("Cannot start file transfer on this connection.")
            return
        }

        if let location = dropPoint, let size = viewportSize {
            let currentDesktopSize = remoteDesktopSize != .zero
                ? remoteDesktopSize
                : CGSize(width: framebuffer.width, height: framebuffer.height)
            let imageWidth = activeCropRect?.width ?? currentDesktopSize.width
            let imageHeight = activeCropRect?.height ?? currentDesktopSize.height
            let safeWidth = max(imageWidth, 1)
            let safeHeight = max(imageHeight, 1)
            let fitScale = min(size.width / safeWidth, size.height / safeHeight)
            let canvasWidth = safeWidth * fitScale * zoomScale
            let canvasHeight = safeHeight * fitScale * zoomScale
            let limitX = max(0, (canvasWidth - size.width) / 2)
            let limitY = max(0, (canvasHeight - size.height) / 2)
            let offsetX = max(-limitX, min(limitX, viewOffset.width))
            let offsetY = max(-limitY, min(limitY, viewOffset.height))
            let originX = (size.width - canvasWidth) / 2 + offsetX
            let originY = (size.height - canvasHeight) / 2 + offsetY

            let relativeX = max(0.0, min(1.0, (location.x - originX) / max(1.0, canvasWidth)))
            let relativeY = max(0.0, min(1.0, (location.y - originY) / max(1.0, canvasHeight)))
            let targetX = UInt16(clamping: Int((activeCropRect?.minX ?? 0) + relativeX * Double(imageWidth)))
            let targetY = UInt16(clamping: Int((activeCropRect?.minY ?? 0) + relativeY * Double(imageHeight)))

            rdp.sendPointerEvent(buttonMask: [.left], x: targetX, y: targetY)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, self.isRDP, self.sessionState == .connected else { return }
                self.rdpClient?.sendPointerEvent(buttonMask: [], x: targetX, y: targetY)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    guard let self, self.isRDP, self.sessionState == .connected else { return }
                    self.sendCommandShortcut("v")
                }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, self.isRDP, self.sessionState == .connected else { return }
                self.sendCommandShortcut("v")
            }
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
