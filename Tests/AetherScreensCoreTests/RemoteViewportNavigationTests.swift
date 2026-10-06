import XCTest
@testable import AetherScreensCore

final class RemoteViewportNavigationTests: XCTestCase {
    private let desktop = CGSize(width: 1920, height: 1080)

    func testFitAndCenteredPointerDoNotPan() {
        XCTAssertEqual(RemoteViewportNavigation.followDelta(cursor: .zero, remoteSize: desktop,
            canvas: CGRect(x: 0, y: 50, width: 400, height: 225), viewport: CGSize(width: 400, height: 600)), .zero)
        XCTAssertEqual(RemoteViewportNavigation.followDelta(cursor: CGPoint(x: 960, y: 540), remoteSize: desktop,
            canvas: CGRect(x: -200, y: -100, width: 800, height: 450), viewport: CGSize(width: 400, height: 250)), .zero)
    }

    func testZoomedPointerRevealsBothEdgesAndRetainsDesktopCoverage() {
        let canvas = CGRect(x: -200, y: -100, width: 800, height: 450)
        let viewport = CGSize(width: 400, height: 250)
        let left = RemoteViewportNavigation.followDelta(cursor: .zero, remoteSize: desktop, canvas: canvas, viewport: viewport)
        XCTAssertEqual(left, CGSize(width: 200, height: 100))
        let right = RemoteViewportNavigation.followDelta(cursor: CGPoint(x: 1919, y: 1079), remoteSize: desktop, canvas: canvas, viewport: viewport)
        XCTAssertEqual(right, CGSize(width: -200, height: -100))
        XCTAssertEqual(RemoteViewportNavigation.followDelta(cursor: .zero, remoteSize: desktop,
            canvas: canvas.offsetBy(dx: left.width, dy: left.height), viewport: viewport), .zero)
        XCTAssertEqual(RemoteViewportNavigation.followDelta(cursor: CGPoint(x: 1919, y: 1079), remoteSize: desktop,
            canvas: canvas.offsetBy(dx: right.width, dy: right.height), viewport: viewport), .zero)
    }

    func testFollowBeginsInsideMarginAndStopsOnceVisible() {
        let canvas = CGRect(x: -200, y: -100, width: 800, height: 450)
        let pointer = CGPoint(x: 1392, y: 540) // Screen x = 380.
        let viewport = CGSize(width: 400, height: 250)
        let delta = RemoteViewportNavigation.followDelta(cursor: pointer, remoteSize: desktop, canvas: canvas, viewport: viewport)
        XCTAssertEqual(delta.width, -8, accuracy: 0.001)
        XCTAssertEqual(delta.height, 0)
        let settled = RemoteViewportNavigation.followDelta(cursor: pointer, remoteSize: desktop,
            canvas: canvas.offsetBy(dx: delta.width, dy: delta.height), viewport: viewport)
        XCTAssertEqual(settled.width, 0, accuracy: 0.001)
    }

    func testLandscapeKeyboardViewportAndCroppedDisplayUseLocalDimensions() {
        let delta = RemoteViewportNavigation.followDelta(cursor: CGPoint(x: 950, y: 550),
            remoteSize: CGSize(width: 1000, height: 600), canvas: CGRect(x: -200, y: -250, width: 1000, height: 600),
            viewport: CGSize(width: 600, height: 180))
        XCTAssertEqual(delta, CGSize(width: -178, height: -148))
    }

    func testInvalidGeometryDoesNotMoveViewport() {
        for size in [CGSize.zero, CGSize(width: CGFloat.nan, height: 100), CGSize(width: 100, height: CGFloat.infinity)] {
            XCTAssertEqual(RemoteViewportNavigation.followDelta(cursor: .zero, remoteSize: desktop,
                canvas: CGRect(x: -200, y: 0, width: 800, height: 450), viewport: size), .zero)
        }
    }
}
