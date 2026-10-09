import XCTest
@testable import AetherScreensCore

final class TightPixelsTests: XCTestCase {
    func testRGBWireOrderAndOpaqueOutput() {
        XCTAssertEqual(TightPixels.expand(Data([255, 0, 0, 0, 255, 0, 0, 0, 255]), colorDepth: .fullColor),
                       Data([0, 0, 255, 255, 0, 255, 0, 255, 255, 0, 0, 255]))
        XCTAssertEqual(TightPixels.fill(Data([12, 34, 56]), width: 2, height: 2, colorDepth: .fullColor),
                       Data(Array(repeating: [UInt8(56), 34, 12, 255], count: 4).flatMap { $0 }))
    }

    func testRGB565WireOrderAndFill() {
        XCTAssertEqual(TightPixels.expand(Data([0, 248, 224, 7, 31, 0]), colorDepth: .rgb565),
                       Data([0, 0, 255, 255, 0, 255, 0, 255, 255, 0, 0, 255]))
        XCTAssertEqual(TightPixels.fill(Data([31, 0]), width: 2, height: 1, colorDepth: .rgb565),
                       Data([255, 0, 0, 255, 255, 0, 0, 255]))
    }

    func testMalformedPixelsAndRectangleBounds() {
        XCTAssertNil(TightPixels.expand(Data([1, 2]), colorDepth: .fullColor))
        XCTAssertNil(TightPixels.expand(Data([1]), colorDepth: .rgb565))
        XCTAssertNil(TightPixels.fill(Data([1, 2, 3, 4]), width: 1, height: 1, colorDepth: .fullColor))
        for (width, height) in [(0, 1), (1, 0), (-1, 1), (Int.max, 2), (2, Int.max), (8193, 8192)] {
            XCTAssertNil(TightPixels.outputByteCount(width: width, height: height))
            XCTAssertNil(TightPixels.fill(Data([1, 2, 3]), width: width, height: height, colorDepth: .fullColor))
        }
        XCTAssertEqual(TightPixels.outputByteCount(width: 8192, height: 8192), 268_435_456)
    }
}
