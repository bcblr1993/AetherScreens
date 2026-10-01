#if os(macOS)
import AppKit
import SwiftUI

/// A native window owns each Mac connection independently of library sheets and
/// SwiftUI visibility changes (including minimizing or covering the window).
@MainActor
public final class SessionWindowManager: NSObject, NSWindowDelegate {
    public static let shared = SessionWindowManager()
    private let registry = SessionRegistry.shared
    private var controllers: [UUID: NSWindowController] = [:]

    @discardableResult
    public func open(_ session: SessionViewModel, reuseExisting: Bool = true) -> UUID {
        let id = registry.register(session, reuseExisting: reuseExisting)
        if controllers[id] != nil {
            focus(id)
            return id
        }
        guard let registered = registry.session(for: id) else { return id }
        let content = SessionWindowContent(session: registered) { [weak self] in self?.close(id) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = registry.sessions.first(where: { $0.id == id })?.title ?? registered.device.name
        window.minSize = NSSize(width: 800, height: 560)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.delegate = self
        window.center()
        if let previous = controllers.values.first?.window {
            _ = window.cascadeTopLeft(from: NSPoint(x: previous.frame.minX + 24, y: previous.frame.maxY - 24))
        }
        let controller = NSWindowController(window: window)
        controllers[id] = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        registered.startSession()
        return id
    }

    public func focus(_ id: UUID) {
        guard let window = controllers[id]?.window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }

    public func close(_ id: UUID) { controllers[id]?.window?.close() }

    public func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = controllers.first(where: { $0.value.window === window })?.key else { return }
        registry.remove(id)?.endSession()
        controllers.removeValue(forKey: id)
    }
}

private struct SessionWindowContent: View {
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    let session: SessionViewModel
    let close: () -> Void

    var body: some View {
        RemoteDesktopView(viewModel: session, managesSessionLifecycle: false, onDisconnect: close)
            .environment(\.locale, languageSettings.locale)
            .tint(.blue)
    }
}
#endif
