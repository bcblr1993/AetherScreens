import Foundation
import Metal

/// Only completed GPU uploads may return buffers here. Outstanding leases are
/// owned by command buffers, not counted against the bounded idle cache.
final class MetalUploadBufferPool: @unchecked Sendable {
    private let device: MTLDevice
    private let byteLimit: Int
    private let countLimit: Int
    private let lock = NSLock()
    private var available: [MTLBuffer] = []
    private var bytes = 0
    private var cachingEnabled = true

    init(device: MTLDevice, byteLimit: Int = 32 * 1024 * 1024, countLimit: Int = 32) {
        self.device = device
        self.byteLimit = max(0, byteLimit)
        self.countLimit = max(0, countLimit)
    }

    func take(length: Int) -> MTLBuffer? {
        guard length > 0 else { return nil }
        lock.lock()
        // Best fit avoids consuming a cached full-desktop buffer for a tiny tile.
        let candidate = available.indices.filter { available[$0].length >= length }
            .min { available[$0].length < available[$1].length }
        if let candidate {
            let buffer = available.remove(at: candidate)
            bytes -= buffer.length
            lock.unlock()
            return buffer
        }
        lock.unlock()
        return device.makeBuffer(length: length, options: .storageModeShared)
    }

    func recycle(_ buffer: MTLBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard cachingEnabled, available.count < countLimit, buffer.length <= byteLimit - bytes else { return }
        available.append(buffer)
        bytes += buffer.length
    }

    func setCachingEnabled(_ enabled: Bool) {
        lock.lock(); defer { lock.unlock() }
        cachingEnabled = enabled
        if !enabled { available.removeAll(); bytes = 0 }
    }

    var cachedBytes: Int { lock.lock(); defer { lock.unlock() }; return bytes }
    var cachedCount: Int { lock.lock(); defer { lock.unlock() }; return available.count }
}
