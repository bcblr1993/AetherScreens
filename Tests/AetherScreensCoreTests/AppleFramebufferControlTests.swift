import XCTest
@testable import AetherScreensCore

final class AppleFramebufferControlTests: XCTestCase {
    func testFirstDisplayArmMessageUsesFullBackingGeometry() {
        XCTAssertEqual(AppleFramebufferControl.arm(width: 3840, height: 2160),
            Data([9,0,0,1,0,0,0,0,0,0,0,0,15,0,8,112]))
    }
    func testExplicitScreenIDUsesNetworkByteOrder() {
        XCTAssertEqual(AppleFramebufferControl.arm(width: 3840, height: 2160, selectedScreen: 0x12345678),
            Data([9,0,0,1,18,52,86,120,0,0,0,0,15,0,8,112]))
        XCTAssertEqual(AppleFramebufferControl.arm(width: 3840, height: 2160, selectedScreen: .max),
            Data([9,0,0,1,255,255,255,255,0,0,0,0,15,0,8,112]))
    }
    func testInvalidOrUnrepresentableGeometryCannotBeSent() {
        for (width,height) in [(0,1), (1,0), (-1,1), (1,-1), (65_536,1), (1,65_536)] {
            XCTAssertNil(AppleFramebufferControl.arm(width: width, height: height))
        }
        XCTAssertEqual(AppleFramebufferControl.arm(width: 65_535, height: 65_535)?.suffix(4), Data([255,255,255,255]))
    }
}
