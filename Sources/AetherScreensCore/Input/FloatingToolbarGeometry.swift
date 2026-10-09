import CoreGraphics

enum FloatingToolbarGeometry {
    static func clamp(_ value: CGFloat, half: CGFloat, length: CGFloat) -> CGFloat {
        let margin = min(half + 8, length / 2)
        return min(max(value, margin), length - margin)
    }

    static func moving(offset: CGSize, delta: CGSize, size: CGSize, toolbar: CGSize) -> CGSize {
        CGSize(width: clamp(size.width / 2 + offset.width + delta.width,
                            half: toolbar.width / 2, length: size.width) - size.width / 2,
               height: clamp(size.height * 0.75 + offset.height + delta.height,
                             half: toolbar.height / 2, length: size.height) - size.height * 0.75)
    }
}
