import Foundation

/// Only gates presentation callbacks; owners separately retain every exact byte count.
struct FileTransferProgressCadence {
    private var lastTime: TimeInterval?
    private var lastBytes: UInt64 = 0

    mutating func shouldPublish(bytes: UInt64, now: TimeInterval) -> Bool {
        guard bytes > lastBytes, now.isFinite, now >= 0 else { return false }
        if let lastTime, now - lastTime < 0.1 { return false }
        lastTime = now
        lastBytes = bytes
        return true
    }
}
