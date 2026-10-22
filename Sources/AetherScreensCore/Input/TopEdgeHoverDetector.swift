#if canImport(AppKit)
import AppKit
import SwiftUI

/// Reports the pointer's distance from the top of the session view without taking any clicks.
/// A tracking area delivers mouse moves to its owner even while other views sit on top of it.
struct TopEdgeHoverDetector: NSViewRepresentable {
    let onPointerY: (CGFloat?) -> Void

    func makeNSView(context: Context) -> TopEdgeHoverView {
        let view = TopEdgeHoverView()
        view.onPointerY = onPointerY
        return view
    }

    func updateNSView(_ view: TopEdgeHoverView, context: Context) {
        view.onPointerY = onPointerY
    }
}

final class TopEdgeHoverView: NSView {
    var onPointerY: ((CGFloat?) -> Void)?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    // Stay out of hit testing so the remote canvas and controls keep every click.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { report(event) }
    override func mouseMoved(with event: NSEvent) { report(event) }

    override func mouseExited(with event: NSEvent) {
        // Flinging the pointer past the top edge into the title bar still means "reach the top".
        let y = convert(event.locationInWindow, from: nil).y
        onPointerY?(y <= 0 ? 0 : nil)
    }

    private func report(_ event: NSEvent) {
        onPointerY?(max(0, convert(event.locationInWindow, from: nil).y))
    }
}
#endif
