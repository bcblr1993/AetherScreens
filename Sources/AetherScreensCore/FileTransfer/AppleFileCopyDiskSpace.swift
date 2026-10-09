import Foundation
import Darwin

/// A preflight estimate, not a reservation or a provider quota guarantee.
enum AppleFileCopyDiskSpace {
    enum Failure: Error { case invalidSize, cannotInspect(Int32), insufficientSpace }
    static func requiredBytes(payloadBytes: UInt64, itemCount: Int, reserve: UInt64 = 1_048_576) throws -> UInt64 {
        guard itemCount > 0 else { throw Failure.invalidSize }
        let overhead = UInt64(itemCount).multipliedReportingOverflow(by: 4096)
        let payload = payloadBytes.addingReportingOverflow(overhead.partialValue)
        let total = payload.partialValue.addingReportingOverflow(reserve)
        guard !overhead.overflow, !payload.overflow, !total.overflow else { throw Failure.invalidSize }
        return total.partialValue
    }
    static func require(availableBytes: UInt64, payloadBytes: UInt64, itemCount: Int) throws {
        guard availableBytes >= (try requiredBytes(payloadBytes: payloadBytes, itemCount: itemCount)) else {
            throw Failure.insufficientSpace
        }
    }
    static func check(directory: URL, payloadBytes: UInt64, itemCount: Int) throws {
        let descriptor = directory.withUnsafeFileSystemRepresentation { path in
            path.map { open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW) } ?? -1
        }
        guard descriptor >= 0 else { throw Failure.cannotInspect(errno) }
        defer { close(descriptor) }
        var volume = statvfs()
        guard fstatvfs(descriptor, &volume) == 0 else { throw Failure.cannotInspect(errno) }
        let blockSize = UInt64(volume.f_frsize > 0 ? volume.f_frsize : volume.f_bsize)
        guard blockSize > 0 else { throw Failure.invalidSize }
        let available = UInt64(volume.f_bavail).multipliedReportingOverflow(by: blockSize)
        guard !available.overflow else { throw Failure.invalidSize }
        try require(availableBytes: available.partialValue, payloadBytes: payloadBytes, itemCount: itemCount)
    }
}
