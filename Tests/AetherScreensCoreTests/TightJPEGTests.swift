import XCTest
import CoreGraphics
import ImageIO
@testable import AetherScreensCore

final class TightJPEGTests: XCTestCase {
    func imageData(type: String) throws -> Data {
        let rgb = Data(Array(repeating: [UInt8(240), 20, 10], count: 16).flatMap { $0 })
        let provider = try XCTUnwrap(CGDataProvider(data: rgb as CFData))
        let image = try XCTUnwrap(CGImage(width: 4, height: 4, bitsPerComponent: 8, bitsPerPixel: 24,
            bytesPerRow: 12, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: 0),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let buffer = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(buffer, type as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return buffer as Data
    }

    func testJPEGProducesOpaqueBGRAWithExpectedColor() throws {
        let pixels = try XCTUnwrap(TightJPEG.decode(try imageData(type: "public.jpeg"), width: 4, height: 4))
        XCTAssertEqual(pixels.count, 64)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            XCTAssertLessThanOrEqual(abs(Int(pixels[offset]) - 10), 5)
            XCTAssertLessThanOrEqual(abs(Int(pixels[offset + 1]) - 20), 5)
            XCTAssertLessThanOrEqual(abs(Int(pixels[offset + 2]) - 240), 5)
            XCTAssertEqual(pixels[offset + 3], 255)
        }
    }

    func testRejectsWrongFormatDimensionsAndIncompleteData() throws {
        let jpeg = try imageData(type: "public.jpeg")
        XCTAssertNil(TightJPEG.decode(jpeg, width: 3, height: 4))
        XCTAssertNil(TightJPEG.decode(jpeg, width: Int.max, height: 4))
        XCTAssertNil(TightJPEG.decode(try imageData(type: "public.png"), width: 4, height: 4))
        XCTAssertNil(TightJPEG.decode(Data(jpeg.prefix(jpeg.count / 2)), width: 4, height: 4))
        XCTAssertNil(TightJPEG.decode(Data(), width: 4, height: 4))
    }
}
