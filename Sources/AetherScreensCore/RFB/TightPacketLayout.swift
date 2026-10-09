import Foundation

enum TightPacketLayout {
    enum Step { case need(Int, pixelPayload: Bool), complete, invalid }

    static func next(_ data: Data, width: Int, height: Int, colorDepth: RFBColorDepth) -> Step {
        guard width <= Int(UInt16.max), height <= Int(UInt16.max),
              TightPixels.outputByteCount(width: width, height: height) != nil else { return .invalid }
        guard let byte = data.first else { return .need(1, pixelPayload: false) }
        guard let control = TightControl(byte) else { return .invalid }
        var offset = 1
        func byteAt(_ position: Int) -> UInt8 { data[data.index(data.startIndex, offsetBy: position)] }
        func body(_ length: Int) -> Step {
            guard data.count <= offset + length else { return .invalid }
            return data.count == offset + length ? .complete : .need(offset + length - data.count, pixelPayload: true)
        }
        func compressedBody() -> Step {
            guard let length = TightCompactLength.parse(data.dropFirst(offset)) else {
                return .need(1, pixelPayload: false)
            }
            guard length.value > 0 else { return .invalid }
            offset += length.bytesConsumed
            return body(length.value)
        }
        switch control.kind {
        case .fill: return body(colorDepth.compactBytesPerPixel)
        case .jpeg: return compressedBody()
        case .basic(_, let explicitFilter):
            var filter = TightBasicDecoder.Filter.copy
            if explicitFilter {
                guard data.count > offset else { return .need(1, pixelPayload: false) }
                guard let parsed = TightBasicDecoder.Filter(rawValue: byteAt(offset)) else { return .invalid }
                filter = parsed
                offset += 1
            }
            var colors = 0
            if filter == .palette {
                guard data.count > offset else { return .need(1, pixelPayload: false) }
                colors = Int(byteAt(offset)) + 1
                guard colors >= 2 else { return .invalid }
                offset += 1
                let paletteEnd = offset + colors * colorDepth.compactBytesPerPixel
                guard data.count >= paletteEnd else { return .need(paletteEnd - data.count, pixelPayload: false) }
                offset = paletteEnd
            }
            guard let expected = TightBasicDecoder.filteredByteCount(width: width, height: height,
                colorDepth: colorDepth, filter: filter, paletteColors: colors) else { return .invalid }
            return expected < 12 ? body(expected) : compressedBody()
        }
    }
}
