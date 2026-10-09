import XCTest
@testable import AetherScreensCore

final class AppleDisplayConfigurationTests: XCTestCase {
    func testMeasuredPhysicalSizeAndInvalidFloatBoundaries() throws {
        let packet = try XCTUnwrap(AppleDisplayConfiguration.fixed(width: 3840, height: 2160,
            physicalSize: (598.380359111388,340.770181217549)))
        XCTAssertEqual(packet[142..<150], Data([68,21,152,88,67,170,98,149]))
        for invalid: Float in [0,-1,.nan,.infinity,-.infinity,.greatestFiniteMagnitude,100_001] {
            XCTAssertNil(AppleDisplayConfiguration.fixed(width: 3840, height: 2160, physicalSize: (invalid,300)))
            XCTAssertNil(AppleDisplayConfiguration.fixed(width: 3840, height: 2160, physicalSize: (500,invalid)))
        }
    }
    func testAggregateAndExplicitDisplaySelectionWireFields() {
        XCTAssertEqual(AppleDisplayConfiguration.selection(), Data([13,1,0,0,0,0,0,0]))
        XCTAssertEqual(AppleDisplayConfiguration.selection(displayID: 0x12345678), Data([13,0,0,0,18,52,86,120]))
    }
    func testHiDPIKeepsBackingAndLogicalDimensionsSeparate() throws {
        let packet = try XCTUnwrap(AppleDisplayConfiguration.fixed(width: 3840, height: 2160, logicalWidth: 1920, logicalHeight: 1080))
        XCTAssertEqual(packet[168..<176], Data([0,0,15,0,0,0,8,112]))
        XCTAssertEqual(packet[176..<184], Data([0,0,7,128,0,0,4,56]))
        for pair in [(0,1080), (1920,0), (3841,1080), (1920,2161)] {
            XCTAssertNil(AppleDisplayConfiguration.fixed(width: 3840, height: 2160, logicalWidth: pair.0, logicalHeight: pair.1))
        }
        XCTAssertNil(AppleDisplayConfiguration.fixed(width: 3840, height: 2160, logicalWidth: 1920))
    }
    func testIndependentFixed4KWireVector() throws {
        let packet = try XCTUnwrap(AppleDisplayConfiguration.fixed(width: 3840, height: 2160))
        var expected = [UInt8](repeating: 0, count: 196)
        let fields: [(Int, [UInt8])] = [
            (0, [29, 0, 0, 192, 0, 1, 0, 1]),
            (12, [0, 184]), (142, [68,126,0,0,68,14,224,0]), (150, [0, 0, 15, 0]), (154, [0, 0, 8, 112]),
            (166, [0, 1]), (168, [0, 0, 15, 0, 0, 0, 8, 112]),
            (176, [0, 0, 15, 0, 0, 0, 8, 112]), (184, [64, 78, 0, 0, 0, 0, 0, 0])
        ]
        for (offset, bytes) in fields { expected.replaceSubrange(offset..<(offset + bytes.count), with: bytes) }
        XCTAssertEqual(Array(packet), expected)
    }
    func testInvalidDimensionsCannotProduceTruncatedWireGeometry() {
        for value in [-1, 0, 65_536, Int.max] {
            XCTAssertNil(AppleDisplayConfiguration.fixed(width: value, height: 2160))
            XCTAssertNil(AppleDisplayConfiguration.fixed(width: 3840, height: value))
        }
        XCTAssertNotNil(AppleDisplayConfiguration.fixed(width: 65_535, height: 1))
    }
}
