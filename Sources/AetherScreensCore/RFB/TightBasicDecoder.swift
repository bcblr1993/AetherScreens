import Foundation

final class TightBasicDecoder {
    enum Filter: UInt8 { case copy = 0, palette = 1, gradient = 2 }
    let streams = TightStreams()

    static func filteredByteCount(width: Int, height: Int, colorDepth: RFBColorDepth,
                                  filter: Filter, paletteColors: Int = 0) -> Int? {
        guard width <= Int(UInt16.max), height <= Int(UInt16.max),
              let outputBytes = TightPixels.outputByteCount(width: width, height: height) else { return nil }
        if filter == .palette {
            guard (2...256).contains(paletteColors) else { return nil }
            return (paletteColors == 2 ? (width + 7) / 8 : width) * height
        }
        return outputBytes / 4 * colorDepth.compactBytesPerPixel
    }

    /// Payload excludes the compact length prefix and optional palette header.
    /// The rectangle reader applies stream resets before calling this method.
    func decode(payload: Data, stream: Int, filter: Filter, palette: Data = Data(),
                width: Int, height: Int, colorDepth: RFBColorDepth) -> Data? {
        guard (0..<4).contains(stream),
              palette.count % colorDepth.compactBytesPerPixel == 0,
              let expected = Self.filteredByteCount(width: width, height: height, colorDepth: colorDepth,
                filter: filter, paletteColors: palette.count / colorDepth.compactBytesPerPixel) else { return nil }
        let data: Data
        if expected < 12 {
            guard payload.count == expected else { return nil }
            data = payload
        } else {
            guard let expanded = streams.decompress(payload, stream: stream, expectedBytes: expected) else { return nil }
            data = expanded
        }
        switch filter {
        case .copy: return TightPixels.expand(data, colorDepth: colorDepth)
        case .palette:
            return TightPalette.decode(indices: data, palette: palette, colorDepth: colorDepth,
                                       width: width, height: height)
        case .gradient:
            return TightGradient.decode(data, width: width, height: height, colorDepth: colorDepth)
        }
    }
}
