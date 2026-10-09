import Foundation

enum TightGradient {
    static func decode(_ residuals: Data, width: Int, height: Int,
                       colorDepth: RFBColorDepth) -> Data? {
        // RFB rectangle dimensions are UInt16. Bound row scratch space as well
        // as the final image, even when this helper is called outside the reader.
        guard width <= Int(UInt16.max), height <= Int(UInt16.max),
              let outputBytes = TightPixels.outputByteCount(width: width, height: height),
              residuals.count == outputBytes / 4 * colorDepth.compactBytesPerPixel else { return nil }
        let maxima = colorDepth == .fullColor ? [255, 255, 255] : [31, 63, 31]
        var previous = [Int](repeating: 0, count: width * 3)
        var current = previous
        var output = Data(count: outputBytes)
        residuals.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { destination in
                let input = source.bindMemory(to: UInt8.self)
                let pixels = destination.bindMemory(to: UInt8.self)
                for y in 0..<height {
                    for x in 0..<width {
                        let position = y * width + x
                        let wire = position * colorDepth.compactBytesPerPixel
                        let packed = colorDepth == .rgb565
                            ? Int(input[wire]) | Int(input[wire + 1]) << 8 : 0
                        for channel in 0..<3 {
                            let left = x == 0 ? 0 : current[(x - 1) * 3 + channel]
                            let above = previous[x * 3 + channel]
                            let aboveLeft = x == 0 ? 0 : previous[(x - 1) * 3 + channel]
                            let prediction = min(max(left + above - aboveLeft, 0), maxima[channel])
                            let residual: Int
                            if colorDepth == .fullColor {
                                residual = Int(input[wire + channel])
                            } else {
                                residual = channel == 0 ? (packed >> 11) & 31
                                    : channel == 1 ? (packed >> 5) & 63 : packed & 31
                            }
                            let value = (prediction + residual) & maxima[channel]
                            current[x * 3 + channel] = value
                            pixels[position * 4 + (2 - channel)] = UInt8(value * 255 / maxima[channel])
                        }
                        pixels[position * 4 + 3] = 255
                    }
                    swap(&previous, &current)
                }
            }
        }
        return output
    }
}
