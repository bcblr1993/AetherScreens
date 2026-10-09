import CoreGraphics

enum PointerArrowShape {
    static var path: CGPath {
        let arrow = CGMutablePath()
        arrow.move(to: .zero)
        for point in [CGPoint(x: 0, y: 23), CGPoint(x: 6, y: 17), CGPoint(x: 11, y: 27),
                      CGPoint(x: 15, y: 25), CGPoint(x: 10, y: 15), CGPoint(x: 19, y: 15)] {
            arrow.addLine(to: point)
        }
        arrow.closeSubpath()
        return arrow
    }
}
