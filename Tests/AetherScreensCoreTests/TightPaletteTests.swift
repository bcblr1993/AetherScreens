import XCTest
@testable import AetherScreensCore

final class TightPaletteTests: XCTestCase {
    func testTwoColorRowsAreMSBFirstAndByteAligned() {
        let palette = Data([255, 0, 0, 0, 0, 255])
        let red: [UInt8] = [0, 0, 255, 255], blue: [UInt8] = [255, 0, 0, 255]
        // Padding bits in each row must not become pixels in the next row.
        let expected = red + blue + red + blue + red + blue
        XCTAssertEqual(TightPalette.decode(indices: Data([0x5f, 0xbf]), palette: palette,
                         colorDepth: .fullColor, width: 3, height: 2), Data(expected))
    }

    func testTwoColorRowsCrossByteBoundary() {
        let expected: [UInt8] = (0..<9).flatMap { $0 == 8 ? [255, 0, 0, 255] : [0, 0, 255, 255] }
        XCTAssertEqual(TightPalette.decode(indices: Data([0, 0x80]), palette: Data([0, 248, 31, 0]),
                         colorDepth: .rgb565, width: 9, height: 1), Data(expected))
    }

    func testMultiColorIndicesAndFullPalette() {
        var palette = Data()
        for value in 0...255 { palette.append(contentsOf: [UInt8(value), 0, 0]) }
        XCTAssertEqual(TightPalette.decode(indices: Data([255, 128, 0]), palette: palette,
                         colorDepth: .fullColor, width: 3, height: 1),
                       Data([0, 0, 255, 255, 0, 0, 128, 255, 0, 0, 0, 255]))
    }

    func testRejectsInvalidPaletteIndexAndLengths() {
        let palette = Data([255, 0, 0, 0, 255, 0, 0, 0, 255])
        for indices in [Data(), Data([0, 1]), Data([3])] {
            XCTAssertNil(TightPalette.decode(indices: indices, palette: palette,
                            colorDepth: .fullColor, width: 1, height: 1))
        }
        for invalid in [Data(), Data([1, 2, 3]), Data([1, 2, 3, 4]), Data(count: 257 * 3)] {
            XCTAssertNil(TightPalette.decode(indices: Data([0]), palette: invalid,
                            colorDepth: .fullColor, width: 1, height: 1))
        }
        XCTAssertNil(TightPalette.decode(indices: Data([0]), palette: palette,
                        colorDepth: .fullColor, width: Int.max, height: 2))
    }
}
