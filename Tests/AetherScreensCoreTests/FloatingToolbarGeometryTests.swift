import XCTest
@testable import AetherScreensCore

final class FloatingToolbarGeometryTests: XCTestCase {
    func testOvershootingEitherEdgeAllowsImmediateReversal() {
        let size = CGSize(width: 1024, height: 768)
        let toolbar = CGSize(width: 720, height: 104)
        for sign: CGFloat in [-1, 1] {
            let edge = FloatingToolbarGeometry.moving(offset: .zero,
                delta: CGSize(width: sign * 2000, height: sign * 2000), size: size, toolbar: toolbar)
            let reversed = FloatingToolbarGeometry.moving(offset: edge,
                delta: CGSize(width: -sign * 10, height: -sign * 10), size: size, toolbar: toolbar)
            XCTAssertEqual(reversed.width, edge.width - sign * 10)
            XCTAssertEqual(reversed.height, edge.height - sign * 10)
        }
    }

    func testToolbarLargerThanViewportRemainsCentered() {
        let offset = FloatingToolbarGeometry.moving(offset: .zero,
            delta: CGSize(width: 500, height: -500), size: CGSize(width: 320, height: 80),
            toolbar: CGSize(width: 720, height: 104))
        XCTAssertEqual(offset, CGSize(width: 0, height: -20))
    }
}
