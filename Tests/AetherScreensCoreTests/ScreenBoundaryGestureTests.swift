import XCTest
@testable import AetherScreensCore

final class ScreenBoundaryGestureTests: XCTestCase {
    func testInwardEdgesAndCorners() {
        let size = CGSize(width: 300, height: 600)
        let edges: [(CGPoint, CGPoint, ScreenEdge)] = [
            (.init(x: 0, y: 300), .init(x: 50, y: 5), .left),
            (.init(x: 300, y: 300), .init(x: -50, y: 5), .right),
            (.init(x: 150, y: 0), .init(x: 5, y: 50), .top),
            (.init(x: 150, y: 600), .init(x: 5, y: -50), .bottom)]
        for (start, delta, edge) in edges {
            XCTAssertEqual(ScreenBoundaryGesture.target(start: start, translation: delta, size: size), .edge(edge))
        }
        let corners: [(CGPoint, CGPoint, TrackpadEngine.HotCorner)] = [
            (.zero, .init(x: 40, y: 40), .topLeft),
            (.init(x: 300, y: 0), .init(x: -40, y: 40), .topRight),
            (.init(x: 0, y: 600), .init(x: 40, y: -40), .bottomLeft),
            (.init(x: 300, y: 600), .init(x: -40, y: -40), .bottomRight)]
        for (start, delta, corner) in corners {
            XCTAssertEqual(ScreenBoundaryGesture.target(start: start, translation: delta, size: size), .corner(corner))
        }
    }

    func testInteriorOutwardShortAndInvalidSwipesDoNotTrigger() {
        let size = CGSize(width: 300, height: 600)
        for (start, delta) in [(CGPoint(x: 150, y: 300), CGPoint(x: 50, y: 0)),
                               (CGPoint(x: 0, y: 300), CGPoint(x: -50, y: 0)),
                               (CGPoint(x: 0, y: 300), CGPoint(x: 10, y: 0)),
                               (CGPoint(x: 0, y: 300), CGPoint(x: 25, y: 50)),
                               (CGPoint(x: CGFloat.nan, y: 0), CGPoint(x: 50, y: 0))] {
            XCTAssertNil(ScreenBoundaryGesture.target(start: start, translation: delta, size: size))
        }
        XCTAssertNil(ScreenBoundaryGesture.target(start: .zero, translation: CGPoint(x: 50, y: 0), size: .zero))
    }
}
