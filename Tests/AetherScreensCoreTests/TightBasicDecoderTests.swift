import XCTest
@testable import AetherScreensCore

final class TightBasicDecoderTests: XCTestCase {
    func testCopyChangesToCompressionAtTwelveBytes() throws {
        let decoder = TightBasicDecoder()
        XCTAssertEqual(decoder.decode(payload: Data([255,0,0]), stream: 0, filter: .copy,
                         width: 1, height: 1, colorDepth: .fullColor), Data([0,0,255,255]))
        let pixels = Data([255,0,0, 0,255,0, 0,0,255, 12,34,56])
        XCTAssertEqual(decoder.decode(payload: try ZRLETestDeflater().compress(pixels), stream: 0, filter: .copy,
                         width: 4, height: 1, colorDepth: .fullColor),
                       Data([0,0,255,255, 0,255,0,255, 255,0,0,255, 56,34,12,255]))
        XCTAssertNil(TightBasicDecoder().decode(payload: pixels, stream: 0, filter: .copy,
                         width: 4, height: 1, colorDepth: .fullColor))
    }

    func testPaletteCompressionThresholdUsesIndicesInsteadOfImageSize() {
        XCTAssertEqual(TightBasicDecoder().decode(payload: Data([0x80]), stream: 2, filter: .palette,
                         palette: Data([255,0,0, 0,0,255]), width: 4, height: 1, colorDepth: .fullColor),
                       Data([255,0,0,255, 0,0,255,255, 0,0,255,255, 0,0,255,255]))
        XCTAssertEqual(TightBasicDecoder.filteredByteCount(width: 9, height: 6, colorDepth: .fullColor,
                         filter: .palette, paletteColors: 2), 12)
        XCTAssertNil(TightBasicDecoder().decode(payload: Data([0]), stream: 4, filter: .copy,
                         width: 1, height: 1, colorDepth: .fullColor))
    }
}
