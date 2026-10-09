import Foundation
import CoreGraphics
import ImageIO

enum TightJPEG {
    static func decode(_ data: Data, width: Int, height: Int) -> Data? {
        guard width <= Int(UInt16.max), height <= Int(UInt16.max),
              let byteCount = TightPixels.outputByteCount(width: width, height: height),
              !data.isEmpty, data.count <= TightCompactLength.maximum,
              let source = CGImageSourceCreateWithData(data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == "public.jpeg",
              CGImageSourceGetCount(source) == 1,
              CGImageSourceGetStatus(source) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == width,
              (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == height,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == width, image.height == height else { return nil }
        var output = Data(count: byteCount)
        let success = output.withUnsafeMutableBytes { destination -> Bool in
            guard let context = CGContext(data: destination.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let pixels = destination.bindMemory(to: UInt8.self)
            for offset in stride(from: 3, to: byteCount, by: 4) { pixels[offset] = 255 }
            return true
        }
        return success ? output : nil
    }
}
