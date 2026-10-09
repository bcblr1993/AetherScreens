import Foundation

/// Owned by one serialized Tight decoder; its dictionaries are not shared with
/// Zlib or ZRLE encoding streams.
final class TightStreams {
    private let streams = (0..<4).map { _ in ZlibDecompressor() }

    /// Reset bits apply to every rectangle, including fill and JPEG rectangles.
    func reset(control: UInt8) {
        for index in 0..<4 where control & (1 << index) != 0 {
            streams[index].reset()
        }
    }

    func decompress(_ data: Data, stream: Int, expectedBytes: Int) -> Data? {
        guard streams.indices.contains(stream), expectedBytes >= 12,
              expectedBytes <= TightPixels.maximumOutputBytes,
              !data.isEmpty, data.count <= TightCompactLength.maximum else { return nil }
        return streams[stream].decompress(data: data, expectedBytes: expectedBytes)
    }
}
