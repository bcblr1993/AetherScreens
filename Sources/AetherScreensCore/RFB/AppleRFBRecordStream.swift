import Foundation

/// Queue-confined encrypted record framing. Retains at most one outer record.
/// Delivery is synchronous; the caller controls downstream buffering.
final class AppleRFBRecordStream {
    private let codec: AppleRFBRecordLayer
    private var pending = Data()
    private var expectedSize = 2
    private var closed = false
    var bufferedByteCount: Int { pending.count }

    init(codec: AppleRFBRecordLayer) { self.codec = codec }

    func append(_ bytes: Data, deliver: (Data) throws -> Void) throws {
        guard !closed else { throw AppleRFBRecordLayer.Failure.closed }
        do {
            var offset = bytes.startIndex
            while offset < bytes.endIndex {
                let count = min(expectedSize - pending.count, bytes.distance(from: offset, to: bytes.endIndex))
                let end = bytes.index(offset, offsetBy: count)
                pending.append(contentsOf: bytes[offset..<end])
                offset = end
                guard pending.count == expectedSize else { continue }
                if expectedSize == 2 {
                    let length = Int(pending[pending.startIndex]) << 8 | Int(pending[pending.index(after: pending.startIndex)])
                    guard length >= 32, length <= 65_520, length % 16 == 0 else {
                        throw AppleRFBRecordLayer.Failure.invalidRecord
                    }
                    expectedSize = length + 2
                } else {
                    let body = try codec.open(pending)
                    pending.removeAll(keepingCapacity: true)
                    expectedSize = 2
                    try deliver(body)
                    guard !closed else { throw AppleRFBRecordLayer.Failure.closed }
                }
            }
        } catch {
            close()
            throw error
        }
    }

    /// An incomplete header/body at EOF is a transport truncation, never a record.
    func finish() throws {
        guard !closed else { throw AppleRFBRecordLayer.Failure.closed }
        let truncated = !pending.isEmpty
        close()
        if truncated { throw AppleRFBRecordLayer.Failure.invalidRecord }
    }

    func close() {
        closed = true
        pending.removeAll()
        codec.close()
    }
}
