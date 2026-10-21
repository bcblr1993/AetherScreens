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
    struct TimeoutError: Error {}
    struct DownloadFailedError: Error {}
    struct CancelledError: Error {}

    static let temporaryDirectoryPrefix = "AetherScreens_Clipboard_"

    private let lock = NSLock()
    private var streamContinuations: [UInt32: CheckedContinuation<Data, Error>] = [:]
    private var currentStreamID: UInt32 = 1000
    private var currentDownloadTask: Task<Void, Never>?
    private let chunkTimeout: TimeInterval
    private let temporaryRoot: URL
    private let staleDirectoryAge: TimeInterval

    public init(
        chunkTimeout: TimeInterval = 8,
        temporaryRoot: URL = FileManager.default.temporaryDirectory,
        staleDirectoryAge: TimeInterval = 24 * 60 * 60
    ) {
        self.chunkTimeout = chunkTimeout
        self.temporaryRoot = temporaryRoot
        self.staleDirectoryAge = staleDirectoryAge
    }

    public func handleFileContentsResponse(_ response: RDPClipboardFileContentsResponse) {
        guard let continuation = takeContinuation(for: response.streamID) else { return }
        if response.ok {
            continuation.resume(returning: response.data)
        } else {
            continuation.resume(throwing: DownloadFailedError())
        }
    }

    public func cancel() {
        lock.lock()
        currentDownloadTask?.cancel()
        currentDownloadTask = nil
        let pending = Array(streamContinuations.values)
        streamContinuations.removeAll()
        lock.unlock()

        for continuation in pending {
            continuation.resume(throwing: CancelledError())
        }
    }

    public func downloadFiles(
        descriptors: [RDPClipboardFileDescriptorW],
        session: any RDPClipboardFileRangeRequester,
        onCompleted: @escaping @Sendable ([URL]) -> Void
    ) {
        cancel()

        let task = Task.detached { [weak self] in
            guard let self else { return }
            self.removeStaleTemporaryDirectories()
            let urls = await self.download(descriptors: descriptors, session: session)
            guard !Task.isCancelled, !urls.isEmpty else { return }
            onCompleted(urls)
        }
        lock.lock()
        currentDownloadTask = task
        lock.unlock()
    }

    /// Converts a remote Windows relative path into safe local path components.
    /// Returns nil when the path is empty or tries to escape the destination directory.
    static func sanitizedRelativeComponents(_ remotePath: String) -> [String]? {
        let rawComponents = remotePath
            .split(whereSeparator: { $0 == "\\" || $0 == "/" })
            .map(String.init)
        var components: [String] = []
        for raw in rawComponents {
            let cleaned = String(raw.unicodeScalars.filter {
                !CharacterSet.controlCharacters.contains($0) && $0 != ":"
            }).trimmingCharacters(in: .whitespaces)
            if cleaned.isEmpty || cleaned == "." { continue }
            if cleaned == ".." { return nil }
            components.append(cleaned)
        }
        return components.isEmpty ? nil : components
    }

    private func download(
        descriptors: [RDPClipboardFileDescriptorW],
        session: any RDPClipboardFileRangeRequester
    ) async -> [URL] {
        let fileManager = FileManager.default
        let tempDir = temporaryRoot
            .appendingPathComponent(Self.temporaryDirectoryPrefix + UUID().uuidString, isDirectory: true)
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            AppLogger.shared.error("Failed to create clipboard download directory: \(error)", category: "RDP")
            return []
        }

        var topLevelNames: [String] = []
        for (index, descriptor) in descriptors.enumerated() {
            guard !Task.isCancelled else { break }
            guard let components = Self.sanitizedRelativeComponents(descriptor.fileName) else {
                AppLogger.shared.error("Rejected unsafe clipboard file path \(descriptor.fileName)", category: "RDP")
                continue
            }
            let targetURL = components.reduce(tempDir) { $0.appendingPathComponent($1) }
            if !topLevelNames.contains(components[0]) {
                topLevelNames.append(components[0])
            }

            if descriptor.isDirectory {
                try? fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true)
                continue
            }
            try? fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            let completed = await downloadFile(
                descriptor: descriptor,
                fileIndex: Int32(index),
                to: targetURL,
                session: session
            )
            if !completed {
                try? fileManager.removeItem(at: targetURL)
            }
        }

        guard !Task.isCancelled else {
            try? fileManager.removeItem(at: tempDir)
            return []
        }
        let urls = topLevelNames
            .map { tempDir.appendingPathComponent($0) }
            .filter { fileManager.fileExists(atPath: $0.path) }
        if urls.isEmpty {
            try? fileManager.removeItem(at: tempDir)
        }
        return urls
    }

    /// Streams one remote file to disk in 64 KB chunks so large files never sit fully in memory.
    private func downloadFile(
        descriptor: RDPClipboardFileDescriptorW,
        fileIndex: Int32,
        to targetURL: URL,
        session: any RDPClipboardFileRangeRequester
    ) async -> Bool {
        guard FileManager.default.createFile(atPath: targetURL.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: targetURL)
        else {
            AppLogger.shared.error("Failed to create clipboard file \(descriptor.fileName)", category: "RDP")
            return false
        }
        defer { try? handle.close() }

        let fileSize = descriptor.fileSize
        let chunkSize: UInt64 = 64 * 1024
        var offset: UInt64 = 0
        while offset < fileSize {
            guard !Task.isCancelled else { return false }
            let bytesToRead = UInt32(min(chunkSize, fileSize - offset))
            do {
                let chunk = try await requestChunk(
                    session: session,
                    fileIndex: fileIndex,
                    position: offset,
                    byteCount: bytesToRead
                )
                guard !chunk.isEmpty, UInt64(chunk.count) <= fileSize - offset else {
                    AppLogger.shared.error("Unexpected chunk size for \(descriptor.fileName) at offset \(offset)", category: "RDP")
                    return false
                }
                try handle.write(contentsOf: chunk)
                offset += UInt64(chunk.count)
            } catch {
                AppLogger.shared.error("Failed to receive chunk for \(descriptor.fileName) at offset \(offset): \(error)", category: "RDP")
                return false
            }
        }
        return !Task.isCancelled
    }

    private func requestChunk(
        session: any RDPClipboardFileRangeRequester,
        fileIndex: Int32,
        position: UInt64,
        byteCount: UInt32
    ) async throws -> Data {
        let streamID = nextStreamID()
        let timeout = chunkTimeout
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            guard !Task.isCancelled else {
                continuation.resume(throwing: CancelledError())
                return
            }
            lock.lock()
            streamContinuations[streamID] = continuation
            lock.unlock()

            // Whichever of response, timeout or cancel takes the continuation first resumes it exactly once.
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.takeContinuation(for: streamID)?.resume(throwing: TimeoutError())
            }

            do {
                try session.requestRemoteFileRange(
                    streamID: streamID,
                    fileIndex: fileIndex,
                    position: position,
                    requestedByteCount: byteCount
                )
            } catch {
                takeContinuation(for: streamID)?.resume(throwing: error)
            }
        }
    }

    private func takeContinuation(for streamID: UInt32) -> CheckedContinuation<Data, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return streamContinuations.removeValue(forKey: streamID)
    }

    private func nextStreamID() -> UInt32 {
        lock.lock()
        defer { lock.unlock() }
        currentStreamID = currentStreamID &+ 1
        if currentStreamID < 1000 { currentStreamID = 1000 }
        return currentStreamID
    }

    /// Previous downloads stay on disk so Finder can paste them later; drop ones older than a day.
    private func removeStaleTemporaryDirectories() {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: temporaryRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-staleDirectoryAge)
        for entry in entries where entry.lastPathComponent.hasPrefix(Self.temporaryDirectoryPrefix) {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff {
                try? fileManager.removeItem(at: entry)
            }
        }
    }
}
