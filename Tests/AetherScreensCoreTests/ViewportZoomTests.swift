import XCTest
@testable import AetherScreensCore

final class ViewportZoomTests: XCTestCase {
    func testOffCenterAnchorKeepsSameRemotePointAcrossSuccessiveZooms() {
        let viewport = CGSize(width: 400, height: 300)
        let anchor = CGPoint(x: 300, y: 100)
        let base = viewport
        let first = ViewportZoom.offset(current: .zero, oldScale: 1, newScale: 2,
            baseCanvas: base, viewport: viewport, anchor: anchor)
        XCTAssertEqual(first, CGSize(width: -100, height: 50))
        let second = ViewportZoom.offset(current: first, oldScale: 2, newScale: 3,
            baseCanvas: base, viewport: viewport, anchor: anchor)
        XCTAssertEqual(second, CGSize(width: -200, height: 100))
        func point(_ offset: CGSize, _ scale: CGFloat) -> CGPoint {
            CGPoint(x: (anchor.x - viewport.width / 2 - offset.width) / scale,
                    y: (anchor.y - viewport.height / 2 - offset.height) / scale)
        }
        XCTAssertEqual(point(.zero, 1), point(first, 2))
        XCTAssertEqual(point(first, 2), point(second, 3))
    }

    func testZoomOutClampsBoundaryAndFittingAxesWithoutBlankSpace() {
        let offset = ViewportZoom.offset(current: CGSize(width: -400, height: 200),
            oldScale: 3, newScale: 1, baseCanvas: CGSize(width: 400, height: 200),
            viewport: CGSize(width: 400, height: 300), anchor: CGPoint(x: 0, y: 300))
        XCTAssertEqual(offset, .zero)
        XCTAssertEqual(ViewportZoom.offset(current: .zero, oldScale: 1, newScale: 2,
            baseCanvas: CGSize(width: 400, height: 300), viewport: CGSize(width: 400, height: 300),
            anchor: CGPoint(x: 200, y: 150)), .zero)
    }
}
