import Foundation
import Darwin

/// System metadata-aware copying with cancellation at copyfile callbacks.
enum AppleFileCopyCancellableTreeCopy {
    enum Failure: Error { case cancelled, cannotCopy(Int32) }
    private final class Context {
        let isCancelled: @Sendable () -> Bool
        let onProgress: @Sendable (UInt64) -> Void
        init(isCancelled: @escaping @Sendable () -> Bool, onProgress: @escaping @Sendable (UInt64) -> Void) {
            self.isCancelled = isCancelled; self.onProgress = onProgress
        }
    }

    static func copy(from source: URL, to destination: URL,
                     isCancelled: @escaping @Sendable () -> Bool = { false },
                     onProgress: @escaping @Sendable (UInt64) -> Void = { _ in }) throws {
        guard !isCancelled() else { throw Failure.cancelled }
        var existing = stat()
        let found = destination.withUnsafeFileSystemRepresentation { path in
            path.map { lstat($0, &existing) } ?? -1
        }
        guard found != 0 else { throw Failure.cannotCopy(EEXIST) }
        guard errno == ENOENT else { throw Failure.cannotCopy(errno) }
        let context = Unmanaged.passRetained(Context(isCancelled: isCancelled, onProgress: onProgress))
        defer { context.release() }
        guard let state = copyfile_state_alloc() else { throw Failure.cannotCopy(ENOMEM) }
        defer { copyfile_state_free(state) }
        let callback: copyfile_callback_t = { what, stage, state, _, _, pointer in
            guard let pointer else { return COPYFILE_QUIT }
            let context = Unmanaged<Context>.fromOpaque(pointer).takeUnretainedValue()
            if what == COPYFILE_COPY_DATA && stage == COPYFILE_PROGRESS, let state {
                var count: off_t = 0
                if copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &count) == 0, count >= 0 {
                    context.onProgress(UInt64(count))
                }
            }
            if context.isCancelled() || what == COPYFILE_RECURSE_ERROR || stage == COPYFILE_ERR { return COPYFILE_QUIT }
            return COPYFILE_CONTINUE
        }
        guard copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(callback, to: UnsafeRawPointer.self)) == 0,
              copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), context.toOpaque()) == 0 else {
            throw Failure.cannotCopy(errno)
        }
        var bufferSize: UInt32 = 65_536
        guard copyfile_state_set(state, UInt32(COPYFILE_STATE_BSIZE), &bufferSize) == 0 else {
            throw Failure.cannotCopy(errno)
        }
        let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_EXCL | COPYFILE_NOFOLLOW)
        let status = source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                copyfile(sourcePath, destinationPath, state, flags)
            }
        }
        let error = errno
        if isCancelled() { throw Failure.cancelled }
        guard status == 0 else { throw Failure.cannotCopy(error) }
    }
}
