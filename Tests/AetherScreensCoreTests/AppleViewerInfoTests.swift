import XCTest
@testable import AetherScreensCore

final class AppleViewerInfoTests: XCTestCase {
    func testVerifiedViewerWireLayoutUsesUInt32ApplicationIDAndMSBFirstMask() {
        let packet = AppleViewerInfo.encode(osVersion: OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 1))
        XCTAssertEqual(packet.count, 66)
        XCTAssertEqual(packet.prefix(34), Data([
            0x21,0,0,62, 0,1, 0,0,0,2, 0,0,0,1, 0,0,0,0, 0,0,0,0,
            0,0,0,27, 0,0,0,0, 0,0,0,1]))
        XCTAssertEqual(packet.suffix(32), Data([
            0xb0,0,8,3,0x90,0,0,0,0,0,0x40,0,0,0,0,0,
            0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]))
    }
}
