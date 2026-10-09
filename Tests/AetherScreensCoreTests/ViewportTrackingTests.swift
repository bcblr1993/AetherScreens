import XCTest
@testable import AetherScreensCore

final class ViewportTrackingTests: XCTestCase {
    func testRepeatedLayoutDoesNotUndoImmediateTouchEdgePan() {
        var projection = ViewportProjection()
        let original = CGRect(x: -395, y: 0, width: 800, height: 600)
        projection.applyLayout(original)
        let delta = ViewportTracking.panDelta(canvas: projection.canvas, viewport: viewport,
            pointer: CGPoint(x: 400, y: 150), movement: CGSize(width: 10, height: 0))
        XCTAssertEqual(delta.width, -5)
        projection.pan(delta)
        projection.applyLayout(original) // unrelated SwiftUI update before pan layout
        XCTAssertEqual(projection.canvas.minX, -400)
        XCTAssertEqual(ViewportTracking.panDelta(canvas: projection.canvas, viewport: viewport,
            pointer: CGPoint(x: 400, y: 150), movement: CGSize(width: 10, height: 0)), .zero)
        projection.applyLayout(original.offsetBy(dx: -5, dy: 0))
        XCTAssertEqual(projection.canvas.minX, -400)
    }

    func testEarlierPanAcknowledgementDoesNotUndoNewerPointerSample() {
        var projection = ViewportProjection()
        projection.applyLayout(zoomed)
        projection.pan(CGSize(width: -10, height: -5))
        let first = projection.canvas
        projection.pan(CGSize(width: -20, height: -15))
        let latest = projection.canvas
        projection.applyLayout(first)
        XCTAssertEqual(projection.canvas, latest)
        projection.applyLayout(latest)
        XCTAssertEqual(projection.canvas, latest)
        projection.applyLayout(viewport)
        XCTAssertEqual(projection.canvas, viewport)
    }

    func testRoundedPanAcknowledgementPreservesNewerSample() {
        var projection = ViewportProjection()
        projection.applyLayout(zoomed)
        projection.pan(CGSize(width: -0.1, height: -0.2))
        let first = projection.canvas
        projection.pan(CGSize(width: -0.3, height: -0.4))
        let latest = projection.canvas
        projection.applyLayout(CGRect(x: first.minX.nextUp, y: first.minY.nextDown,
            width: first.width, height: first.height))
        XCTAssertEqual(projection.canvas, latest)
        // A similar origin must not hide an actual canvas-size change.
        projection.applyLayout(CGRect(x: latest.minX, y: latest.minY,
            width: latest.width + 0.1, height: latest.height))
        XCTAssertEqual(projection.canvas.width, latest.width + 0.1)
    }

    func testChangedLayoutReplacesProjectionAfterResizeOrZoom() {
        var projection = ViewportProjection()
        projection.applyLayout(zoomed)
        projection.pan(CGSize(width: -20, height: -30))
        projection.applyLayout(viewport)
        XCTAssertEqual(projection.canvas, viewport)
        projection.applyLayout(zoomed)
        XCTAssertEqual(projection.canvas, zoomed)
    }

    let viewport = CGRect(x: 0, y: 0, width: 400, height: 300)
    let zoomed = CGRect(x: -200, y: -150, width: 800, height: 600)

    func testHardwarePointerRemainsAtItsLocationAfterPanMapping() {
        let point = CGPoint(x: 390, y: 290)
        let delta = pan(point, CGSize(width: 10, height: 10))
        let moved = zoomed.offsetBy(dx: delta.width, dy: delta.height)
        let remote = CGPoint(x: (point.x - moved.minX) * 1920 / moved.width,
                             y: (point.y - moved.minY) * 1080 / moved.height)
        XCTAssertEqual(moved.minX + remote.x * moved.width / 1920, point.x, accuracy: 0.001)
        XCTAssertEqual(moved.minY + remote.y * moved.height / 1080, point.y, accuracy: 0.001)
        XCTAssertEqual(ViewportTracking.panDelta(canvas: moved, viewport: viewport,
            pointer: point, movement: .zero), .zero)
    }

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
