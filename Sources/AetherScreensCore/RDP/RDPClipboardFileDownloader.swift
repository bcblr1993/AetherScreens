import Foundation
import RDPKit

public protocol RDPClipboardFileRangeRequester: AnyObject, Sendable {
    func requestRemoteFileRange(
        streamID: UInt32,
        fileIndex: Int32,
        position: UInt64,
        requestedByteCount: UInt32
    ) throws
}

extension RDPClipboardSession: RDPClipboardFileRangeRequester {
    public func requestRemoteFileRange(
        streamID: UInt32,
        fileIndex: Int32,
        position: UInt64,
        requestedByteCount: UInt32
    ) throws {
        try self.requestRemoteFileRange(
            streamID: streamID,
            fileIndex: fileIndex,
            position: position,
            requestedByteCount: requestedByteCount,
            clipDataID: nil
        )
    }
}

/// Downloads files advertised by a remote Windows host via MS-RDPECLIP into local temporary storage.
public final class RDPClipboardFileDownloader: @unchecked Sendable {
    private struct TimeoutError: Error {}
    private struct DownloadFailedError: Error {}

    private let lock = NSLock()
    private var streamContinuations: [UInt32: CheckedContinuation<Data, Error>] = [:]
    private var currentStreamID: UInt32 = 1000
    private var isDownloading = false
    private var currentDownloadTask: Task<Void, Never>?

    public init() {}

    private func setDownloading(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        isDownloading = value
    }

    private func storeContinuation(_ continuation: CheckedContinuation<Data, Error>, for streamID: UInt32) {
        lock.lock()
        defer { lock.unlock() }
        streamContinuations[streamID] = continuation
    }

    private func removeContinuation(for streamID: UInt32) {
        lock.lock()
        defer { lock.unlock() }
        streamContinuations.removeValue(forKey: streamID)
    }

    public func handleFileContentsResponse(_ response: RDPClipboardFileContentsResponse) {
        lock.lock()
        let continuation = streamContinuations.removeValue(forKey: response.streamID)
        lock.unlock()

        if response.ok {
            continuation?.resume(returning: response.data)
        } else {
            continuation?.resume(throwing: DownloadFailedError())
        }
    }

    public func cancel() {
        lock.lock()
        currentDownloadTask?.cancel()
        currentDownloadTask = nil
        isDownloading = false
        for continuation in streamContinuations.values {
            struct CancelError: Error {}
            continuation.resume(throwing: CancelError())
        }
        streamContinuations.removeAll()
        lock.unlock()
    }

    public func downloadFiles(
        descriptors: [RDPClipboardFileDescriptorW],
        session: any RDPClipboardFileRangeRequester,
        onCompleted: @escaping @Sendable ([URL]) -> Void
    ) {
        cancel()
        setDownloading(true)

        currentDownloadTask = Task.detached { [weak self] in
            guard let self else { return }
            defer { self.setDownloading(false) }

            var downloadedURLs: [URL] = []
            var topLevelNames: [String] = []
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("AetherScreens_Clipboard_\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            for (index, descriptor) in descriptors.enumerated() {
                guard !Task.isCancelled else { break }

                let relativePath = descriptor.fileName.replacingOccurrences(of: "\\", with: "/")
                let targetURL = tempDir.appendingPathComponent(relativePath)
                let topName = relativePath.components(separatedBy: "/").first ?? relativePath
                if !topLevelNames.contains(topName) {
                    topLevelNames.append(topName)
                }

                if descriptor.isDirectory {
                    try? FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
                    continue
                }

                try? FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)

                let fileSize = descriptor.fileSize
                if fileSize == 0 {
                    FileManager.default.createFile(atPath: targetURL.path, contents: Data())
                    continue
                }

                // Download file in 64 KB chunks
                let chunkSize: UInt32 = 64 * 1024
                var offset: UInt64 = 0
                var fileData = Data()
                fileData.reserveCapacity(Int(min(fileSize, 50 * 1024 * 1024)))
                var fileFailed = false

                while offset < fileSize && !Task.isCancelled {
                    let remaining = fileSize - offset
                    let bytesToRead = UInt32(min(UInt64(chunkSize), remaining))
                    let streamID = self.nextStreamID()

                    do {
                        let chunk = try await withThrowingTaskGroup(of: Data.self) { group in
                            group.addTask {
                                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                                    self.storeContinuation(continuation, for: streamID)

                                    do {
                                        try session.requestRemoteFileRange(
                                            streamID: streamID,
                                            fileIndex: Int32(index),
                                            position: offset,
                                            requestedByteCount: bytesToRead
                                        )
                                    } catch {
                                        self.removeContinuation(for: streamID)
                                        continuation.resume(throwing: error)
                                    }
                                }
                            }

                            group.addTask {
                                try await Task.sleep(nanoseconds: 8_000_000_000) // 8s timeout per chunk
                                throw TimeoutError()
                            }

                            guard let first = try await group.next() else {
                                throw DownloadFailedError()
                            }
                            group.cancelAll()
                            return first
                        }

                        guard !chunk.isEmpty else {
                            fileFailed = true
                            break
                        }
                        fileData.append(chunk)
                        offset += UInt64(chunk.count)
                    } catch {
                        self.removeContinuation(for: streamID)
                        fileFailed = true
                        AppLogger.shared.error("Failed to receive chunk for \(descriptor.fileName) at offset \(offset): \(error)", category: "RDP")
                        break
                    }
                }

                if !fileFailed && !Task.isCancelled && fileData.count == Int(fileSize) {
                    do {
                        try fileData.write(to: targetURL)
                    } catch {
                        AppLogger.shared.error("Failed to write clipboard file \(descriptor.fileName): \(error)", category: "RDP")
                    }
                }
            }

            for topName in topLevelNames {
                let url = tempDir.appendingPathComponent(topName)
                if FileManager.default.fileExists(atPath: url.path) {
                    downloadedURLs.append(url)
                }
            }

            guard !Task.isCancelled && !downloadedURLs.isEmpty else { return }
            onCompleted(downloadedURLs)
        }
    }

    private func nextStreamID() -> UInt32 {
        lock.lock()
        defer { lock.unlock() }
        currentStreamID = currentStreamID &+ 1
        if currentStreamID < 1000 { currentStreamID = 1000 }
        return currentStreamID
    }
}
