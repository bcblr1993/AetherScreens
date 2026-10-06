import XCTest
@testable import AetherScreensCore

final class ViewportTrackingTests: XCTestCase {
    let viewport = CGRect(x: 0, y: 0, width: 400, height: 300)
    let zoomed = CGRect(x: -200, y: -150, width: 800, height: 600)

    func testFollowsAllEdgesAndDiagonal() {
        XCTAssertEqual(pan(CGPoint(x: 390, y: 290), CGSize(width: 10, height: 10)),
                       CGSize(width: -22, height: -22))
        XCTAssertEqual(pan(CGPoint(x: 10, y: 10), CGSize(width: -10, height: -10)),
                       CGSize(width: 22, height: 22))
    }

    func testCenterAndInwardMovementDoNotPan() {
        XCTAssertEqual(pan(CGPoint(x: 200, y: 150), CGSize(width: 10, height: 10)), .zero)
        XCTAssertEqual(pan(CGPoint(x: 390, y: 290), CGSize(width: -10, height: -10)), .zero)
        XCTAssertEqual(pan(CGPoint(x: 390, y: 290), .zero), .zero)
    }

    func testDesktopEdgesClampWithoutBlankSpace() {
        let result = ViewportTracking.panDelta(canvas: CGRect(x: -395, y: 0, width: 800, height: 600),
            viewport: viewport, pointer: CGPoint(x: 400, y: 0), movement: CGSize(width: 10, height: -10))
        XCTAssertEqual(result, CGSize(width: -5, height: 0))
    }

    func testFitAndLetterboxedAxesStayFixed() {
        XCTAssertEqual(ViewportTracking.panDelta(canvas: viewport, viewport: viewport,
            pointer: CGPoint(x: 399, y: 299), movement: CGSize(width: 10, height: 10)), .zero)
        XCTAssertEqual(ViewportTracking.panDelta(canvas: CGRect(x: -200, y: 50, width: 800, height: 200),
            viewport: viewport, pointer: CGPoint(x: 390, y: 240), movement: CGSize(width: 10, height: 10)),
            CGSize(width: -22, height: 0))
    }

    private func pan(_ pointer: CGPoint, _ movement: CGSize) -> CGSize {
        ViewportTracking.panDelta(canvas: zoomed, viewport: viewport, pointer: pointer, movement: movement)
    }
}
