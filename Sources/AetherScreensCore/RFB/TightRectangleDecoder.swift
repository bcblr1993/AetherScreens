import Foundation

/// Incremental framing is side-effect-free until an entire rectangle is present.
/// Call only on the serial decode worker; each successful decode consumes once.
final class TightRectangleDecoder {
    enum Result {
        case incomplete
        case invalid
        case decoded(Data, bytesConsumed: Int)
    }
    private let basic = TightBasicDecoder()

    func decode(_ data: Data, width: Int, height: Int, colorDepth: RFBColorDepth) -> Result {
        guard width <= Int(UInt16.max), height <= Int(UInt16.max),
              TightPixels.outputByteCount(width: width, height: height) != nil else { return .invalid }
        guard let byte = data.first else { return .incomplete }
        guard let control = TightControl(byte) else { return .invalid }
        var offset = 1
        var filter = TightBasicDecoder.Filter.copy
        var palette = Data()
        var stream = 0
        let payloadLength: Int
        func slice(_ start: Int, _ count: Int) -> Data {
            Data(data[data.index(data.startIndex, offsetBy: start)..<data.index(data.startIndex, offsetBy: start + count)])
        }
        switch control.kind {
        case .fill: payloadLength = colorDepth.compactBytesPerPixel
        case .jpeg:
            guard let length = TightCompactLength.parse(data.dropFirst(offset)) else { return .incomplete }
            guard length.value > 0 else { return .invalid }
            offset += length.bytesConsumed
            payloadLength = length.value
        case .basic(let selectedStream, let explicitFilter):
            stream = selectedStream
            if explicitFilter {
                guard data.count > offset else { return .incomplete }
                guard let selectedFilter = TightBasicDecoder.Filter(rawValue: data[data.index(data.startIndex, offsetBy: offset)]) else { return .invalid }
                filter = selectedFilter
                offset += 1
            }
            if filter == .palette {
                guard data.count > offset else { return .incomplete }
                let colors = Int(data[data.index(data.startIndex, offsetBy: offset)]) + 1
                guard colors >= 2 else { return .invalid }
                offset += 1
                let paletteBytes = colors * colorDepth.compactBytesPerPixel
                guard data.count - offset >= paletteBytes else { return .incomplete }
                palette = slice(offset, paletteBytes)
                offset += paletteBytes
            }
            guard let expected = TightBasicDecoder.filteredByteCount(width: width, height: height,
                colorDepth: colorDepth, filter: filter, paletteColors: palette.count / colorDepth.compactBytesPerPixel) else { return .invalid }
            if expected < 12 {
                payloadLength = expected
            } else {
                guard let length = TightCompactLength.parse(data.dropFirst(offset)) else { return .incomplete }
                guard length.value > 0 else { return .invalid }
                offset += length.bytesConsumed
                payloadLength = length.value
            }
        }
        guard data.count - offset >= payloadLength else { return .incomplete }
        let payload = slice(offset, payloadLength)
        basic.streams.reset(control: control.resetMask)
        let pixels: Data?
        switch control.kind {
        case .fill: pixels = TightPixels.fill(payload, width: width, height: height, colorDepth: colorDepth)
        case .jpeg: pixels = TightJPEG.decode(payload, width: width, height: height)
        case .basic:
            pixels = basic.decode(payload: payload, stream: stream, filter: filter, palette: palette,
                                  width: width, height: height, colorDepth: colorDepth)
        }
        guard let pixels else { return .invalid }
        return .decoded(pixels, bytesConsumed: offset + payloadLength)
    }
}
