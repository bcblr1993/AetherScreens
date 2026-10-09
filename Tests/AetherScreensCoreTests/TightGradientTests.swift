import XCTest
@testable import AetherScreensCore

final class TightGradientTests: XCTestCase {
    func testRGBPredictionClampsAtBothLimitsAndWraps() {
        // Reconstructed RGB rows: (250,10,100), (255,0,150),
        //                         (0,20,80), (10,30,100).
        // Last prediction is (5,10,130), with modular residuals for decreases.
        let residuals = Data([250,10,100, 5,246,50, 6,10,236, 5,20,226])
        XCTAssertEqual(TightGradient.decode(residuals, width: 2, height: 2, colorDepth: .fullColor),
                       Data([100,10,250,255, 150,0,255,255, 80,20,0,255, 100,30,10,255]))
        // At the final pixel, red predictor 250 + 250 - 0 clamps to 255.
        XCTAssertEqual(TightGradient.decode(Data([0,0,0, 250,0,0, 250,0,0, 1,0,0]),
                         width: 2, height: 2, colorDepth: .fullColor),
                       Data([0,0,0,255, 0,0,250,255, 0,0,250,255, 0,0,0,255]))
    }

    func testRGB565UsesSeparateComponentModuli() {
        // Red max followed by +1 wraps red; green +63 then +1 wraps green.
        XCTAssertEqual(TightGradient.decode(Data([224,255, 32,8]), width: 2, height: 1, colorDepth: .rgb565),
                       Data([0,255,255,255, 0,0,0,255]))
    }

    func testRowsDoNotCarryLeftPixelAcrossBoundary() {
        XCTAssertEqual(TightGradient.decode(Data([10,20,30, 1,2,3]), width: 1, height: 2, colorDepth: .fullColor),
                       Data([30,20,10,255, 33,22,11,255]))
    }

    func testInvalidDimensionsAndResidualLengths() {
        for data in [Data(), Data([1,2]), Data([1,2,3,4])] {
            XCTAssertNil(TightGradient.decode(data, width: 1, height: 1, colorDepth: .fullColor))
        }
        XCTAssertNil(TightGradient.decode(Data([0]), width: 1, height: 1, colorDepth: .rgb565))
        XCTAssertNil(TightGradient.decode(Data(), width: Int.max, height: 2, colorDepth: .fullColor))
        XCTAssertNil(TightGradient.decode(Data(count: 65_536 * 3), width: 65_536, height: 1, colorDepth: .fullColor))
    }
}
