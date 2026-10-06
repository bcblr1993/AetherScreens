import Foundation
import CoreGraphics

public enum ScreenEdge: CaseIterable, Sendable {
    case left, right, top, bottom
    public func point(width: CGFloat, height: CGFloat) -> CGPoint {
        switch self {
        case .left: return CGPoint(x: 0, y: height / 2)
        case .right: return CGPoint(x: max(0, width - 1), y: height / 2)
        case .top: return CGPoint(x: width / 2, y: 0)
        case .bottom: return CGPoint(x: width / 2, y: max(0, height - 1))
        }
    }
}

public enum ScreenBoundaryTarget: Equatable, Sendable {
    case edge(ScreenEdge)
    case corner(TrackpadEngine.HotCorner)
}

/// Classifies an inward swipe without depending on UIKit recognizer timing.
public enum ScreenBoundaryGesture {
    public static func target(start: CGPoint, translation: CGPoint, size: CGSize) -> ScreenBoundaryTarget? {
        guard start.x.isFinite, start.y.isFinite, translation.x.isFinite, translation.y.isFinite,
              size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              start.x >= 0, start.y >= 0, start.x <= size.width, start.y <= size.height else { return nil }
        let margin = min(32, min(size.width, size.height) * 0.1)
        let left = start.x <= margin, right = start.x >= size.width - margin
        let top = start.y <= margin, bottom = start.y >= size.height - margin
        let inwardX = left ? translation.x : right ? -translation.x : 0
        let inwardY = top ? translation.y : bottom ? -translation.y : 0
        if (left || right) && (top || bottom), inwardX >= 12, inwardY >= 12,
           max(inwardX, inwardY) <= min(inwardX, inwardY) * 3 {
            return .corner(top ? (left ? .topLeft : .topRight) : (left ? .bottomLeft : .bottomRight))
        }
        if inwardX >= 24, abs(translation.y) <= inwardX * 0.5 { return .edge(left ? .left : .right) }
        if inwardY >= 24, abs(translation.x) <= inwardY * 0.5 { return .edge(top ? .top : .bottom) }
        return nil
    }
}
