import XCTest
@testable import AetherScreensCore

final class TightControlTests: XCTestCase {
    func testEveryControlByteSeparatesResetsFromPayloadLayout() throws {
        for value in 0...255 {
            let byte = UInt8(value)
            let control = TightControl(byte)
            if value >= 160 {
                XCTAssertNil(control)
                continue
            }
            let parsed = try XCTUnwrap(control)
            XCTAssertEqual(parsed.resetMask, byte & 15)
            switch value >> 4 {
            case 0...7:
                XCTAssertEqual(parsed.kind, .basic(stream: (value >> 4) & 3, explicitFilter: value & 64 != 0))
            case 8: XCTAssertEqual(parsed.kind, .fill)
            case 9: XCTAssertEqual(parsed.kind, .jpeg)
            default: XCTFail("Unexpected accepted control")
            }
        }
    }
}
