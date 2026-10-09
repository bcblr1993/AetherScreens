import XCTest
@testable import AetherScreensCore

final class ExternalPointerGeometryTests: XCTestCase {
    func testSelectedRightMonitorUsesItsGlobalOriginAndLetterboxOffset() {
        let monitor = CGRect(x: 320, y: 0, width: 320, height: 360)
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(ExternalPointerGeometry.position(CGPoint(x: 480, y: 180), remoteRect: monitor, bounds: screen), CGPoint(x: 960, y: 540))
        XCTAssertEqual(ExternalPointerGeometry.position(CGPoint(x: 320, y: 0), remoteRect: monitor, bounds: screen), CGPoint(x: 480, y: 0))
        XCTAssertNil(ExternalPointerGeometry.position(CGPoint(x: 100, y: 180), remoteRect: monitor, bounds: screen))
    }

    func testWideDesktopOnPortraitDisplayUsesVerticalLetterboxing() {
        XCTAssertEqual(ExternalPointerGeometry.position(.zero, remoteRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), bounds: CGRect(x: 0, y: 0, width: 1080, height: 1920)), CGPoint(x: 0, y: 656.25))
    }

    func testEmptyViewAndNonfiniteGeometryDoNotProduceCursorPositions() {
        let remote = CGRect(x: 0, y: 0, width: 640, height: 480)
        XCTAssertNil(ExternalPointerGeometry.position(.zero, remoteRect: remote, bounds: .zero))
        XCTAssertNil(ExternalPointerGeometry.position(.zero, remoteRect: .zero, bounds: remote))
        XCTAssertNil(ExternalPointerGeometry.position(.zero, remoteRect: remote, bounds: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 480)))
    }
}
