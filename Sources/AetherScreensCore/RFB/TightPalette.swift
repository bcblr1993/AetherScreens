import Foundation

enum TightPalette {
    static func decode(indices: Data, palette: Data, colorDepth: RFBColorDepth,
                       width: Int, height: Int) -> Data? {
        let pixelBytes = colorDepth.compactBytesPerPixel
        guard let outputBytes = TightPixels.outputByteCount(width: width, height: height),
              palette.count % pixelBytes == 0 else { return nil }
        let colors = palette.count / pixelBytes
        guard (2...256).contains(colors),
              let expanded = TightPixels.expand(palette, colorDepth: colorDepth) else { return nil }
        let rowBytes = colors == 2 ? (width + 7) / 8 : width
        guard indices.count == rowBytes * height else { return nil }
        var output = Data(count: outputBytes)
        let valid = indices.withUnsafeBytes { source in
            expanded.withUnsafeBytes { table in
                output.withUnsafeMutableBytes { destination -> Bool in
                    let input = source.bindMemory(to: UInt8.self)
                    let entries = table.bindMemory(to: UInt8.self)
                    let pixels = destination.bindMemory(to: UInt8.self)
                    for y in 0..<height {
                        for x in 0..<width {
                            let index: Int
                            if colors == 2 {
                                index = Int((input[y * rowBytes + x / 8] >> (7 - x % 8)) & 1)
                            } else {
                                index = Int(input[y * rowBytes + x])
                            }
                            guard index < colors else { return false }
                            let target = (y * width + x) * 4
                            for component in 0..<4 {
                                pixels[target + component] = entries[index * 4 + component]
                            }
                        }
                    }
                    return true
                }
            }
        }
        return valid ? output : nil
    }
}
