import Foundation
import Darwin

/// Single-worker bounded upload reader. The negotiated owner sends command 101
/// first and command 104 only after all items; reads are not receiver ACKs.
final class AppleFileCopyForkReader {
    enum Failure: Error { case unsupportedItem, invalidSource, invalidBlockSize, sourceTruncated, unavailable }
    private let sessionID: UInt32
    private let blockSize: Int
    private var handles: [FileHandle] = []
    private var remaining: [UInt64] = []
    private var forkIndex = 0
    private var cancelled = false

    init(item: AppleFileCopyItem, sessionID: UInt32, dataURL: URL, resourceURL: URL?,
         blockSize: Int = 65_536) throws {
        guard item.catalogHeader.count == 104, !item.isDirectory,
              item.symbolicLinkTarget == nil else { throw Failure.unsupportedItem }
        // Common header consumes 8 payload bytes; command 102 consumes 4 more.
        guard (1...1_048_564).contains(blockSize) else { throw Failure.invalidBlockSize }
        self.sessionID = sessionID
        self.blockSize = blockSize
        do {
            // The receiver consumes the data fork first, then the resource fork.
            handles.append(try Self.openSource(dataURL, expectedBytes: item.dataForkByteCount))
            remaining.append(item.dataForkByteCount)
            if item.resourceForkByteCount > 0 {
                guard let resourceURL else { throw Failure.invalidSource }
                handles.append(try Self.openSource(resourceURL, expectedBytes: item.resourceForkByteCount))
                remaining.append(item.resourceForkByteCount)
            }
        } catch {
            cancel()
            throw error
        }
    }

    private static func openSource(_ url: URL, expectedBytes: UInt64) throws -> FileHandle {
        guard url.isFileURL else { throw Failure.invalidSource }
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            path.map { open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) } ?? -1
        }
        guard descriptor >= 0 else { throw Failure.invalidSource }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size >= 0, UInt64(info.st_size) == expectedBytes else {
            close(descriptor)
            throw Failure.invalidSource
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    /// Caller retains a returned packet until its send queue accepts it. Calling
    /// again advances the source; this reader performs no queue retry itself.
    func nextMessage() throws -> AppleFileCopyMessage? {
        guard !cancelled else { throw Failure.unavailable }
        do {
            while forkIndex < handles.count, remaining[forkIndex] == 0 {
                try handles[forkIndex].close()
                forkIndex += 1
            }
            guard forkIndex < handles.count else { return nil }
            let count = Int(min(UInt64(blockSize), remaining[forkIndex]))
            var bytes = Data()
            while bytes.count < count {
                guard let part = try handles[forkIndex].read(upToCount: count - bytes.count), !part.isEmpty else {
                    throw Failure.sourceTruncated
                }
                bytes.append(part)
            }
            remaining[forkIndex] -= UInt64(count)
            var body = Data()
            withUnsafeBytes(of: UInt32(count).bigEndian) { body.append(contentsOf: $0) }
            body.append(bytes)
            return AppleFileCopyMessage(version: 1, command: 102, sessionID: sessionID, body: body)
        } catch {
            cancel()
            throw error
        }
    }

    func cancel() {
        cancelled = true
        for handle in handles { try? handle.close() }
        handles.removeAll()
        remaining.removeAll()
    }

    deinit { cancel() }
}
