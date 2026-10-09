import AppKit

// Owned remote-Mac fixture: no input, capture, clipboard, or persistent settings.
@MainActor
final class PatternView: NSView {
    private var tick = 0
    private var drawPasses = 0
    override func draw(_ dirtyRect: NSRect) {
        drawPasses += 1
        if drawPasses <= 2 { print("Owned pattern draw pass \(drawPasses), tick \(tick)") }
        NSColor.black.setFill()
        bounds.fill()
        let color = tick.isMultiple(of: 2) ? NSColor.systemTeal : NSColor.systemOrange
        color.setFill()
        NSRect(x: 24 + (tick % 8) * 32, y: 24, width: 64, height: 64).fill()
        let text = "AetherScreens QA · \(tick)" as NSString
        text.draw(at: NSPoint(x: 24, y: 108), withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 20, weight: .medium),
            .foregroundColor: NSColor.white
        ])
    }
    @objc func finish() {
        print("Owned pattern finished: tick \(tick), draw passes \(drawPasses)")
        window?.close()
        NSApplication.shared.terminate(nil)
    }
    @objc func advance() {
        tick += 1
        needsDisplay = true
    }
    @objc func reportDisplayGeometry(_ notification: Notification) {
        guard let window, let screen = window.screen else { return }
        let content = window.convertToScreen(convert(bounds, to: nil))
        print("Owned changed screen logical rect: \(NSStringFromRect(screen.frame)), backing scale \(screen.backingScaleFactor), content rect \(NSStringFromRect(content))")
    }
}

@main
struct PatternMain {
    @MainActor static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count == 2, let seconds = Double(arguments[1]), (5...180).contains(seconds) else {
            fputs("Usage: native-display-pattern <5...180 seconds>\n", stderr)
            exit(2)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let view = PatternView(frame: NSRect(x: 0, y: 0, width: 360, height: 160))
        let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 360, height: 160),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "AetherScreens temporary test pattern"
        window.contentView = view
        // Explicit screen coordinates avoid AppKit adding visibleFrame.origin
        // when a side Dock shifts the default screen's usable coordinate space.
        window.setFrameOrigin(NSPoint(x: 120, y: 40))
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        NotificationCenter.default.addObserver(view, selector: #selector(PatternView.reportDisplayGeometry(_:)),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let contentOnScreen = window.convertToScreen(view.convert(view.bounds, to: nil))
        print("Owned content rect on screen: \(NSStringFromRect(contentOnScreen))")
        _ = Timer.scheduledTimer(timeInterval: 1, target: view,
                                 selector: #selector(PatternView.advance), userInfo: nil, repeats: true)
        _ = Timer.scheduledTimer(timeInterval: seconds, target: view,
                                 selector: #selector(PatternView.finish), userInfo: nil, repeats: false)
        if let screen = NSScreen.main {
            print("Owned pattern logical screen: \(screen.frame.width)x\(screen.frame.height), backing scale \(screen.backingScaleFactor)")
            print("Owned screen visible rect: \(NSStringFromRect(screen.visibleFrame))")
        }
        print("Owned display pattern ready; lifetime \(seconds) seconds; no capture or input")
        app.run()
    }
}
