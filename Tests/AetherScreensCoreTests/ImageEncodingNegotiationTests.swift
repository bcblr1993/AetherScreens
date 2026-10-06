import XCTest
@testable import AetherScreensCore

final class ImageEncodingNegotiationTests: XCTestCase {
    func testImplementedImageEncodingNegotiationHasStableWireFallbacks() {
        let generic = RFBEncoder.encodeSetEncodings(RFBEncoder.sessionEncodings(supportsAppleDisplayMetadata: false))
        XCTAssertEqual(generic, Data([
            2, 0, 0, 6,
            0, 0, 0, 16, // ZRLE
            0, 0, 0, 6, // Zlib
            0, 0, 0, 1, // CopyRect
            255, 255, 255, 33, // DesktopSize (-223)
            255, 255, 254, 204, // ExtendedDesktopSize (-308)
            0, 0, 0, 0 // Raw
        ]))
        let apple = RFBEncoder.encodeSetEncodings(RFBEncoder.sessionEncodings(supportsAppleDisplayMetadata: true))
        XCTAssertEqual(apple.prefix(4), Data([2, 0, 0, 8]))
        XCTAssertEqual(apple.dropFirst(4).prefix(24), generic.dropFirst(4))
        XCTAssertEqual(apple.suffix(8), Data([0, 0, 4, 77, 0, 0, 4, 81]))
    }
}
