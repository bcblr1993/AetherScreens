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

    /// Only the minimum size constrains the window. The default options also apply the content's
    /// intrinsic size, so a wide child (such as the keyboard toolbar) would resize and move the window.
    static func makeHostingView<Content: View>(_ content: Content) -> NSHostingView<Content> {
        let view = NSHostingView(rootView: content)
        view.sizingOptions = [.minSize]
        return view
    }

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
        window.contentView = Self.makeHostingView(content)
        window.delegate = self
        window.center()
        if let previous = controllers.values.first?.window {
            _ = window.cascadeTopLeft(from: NSPoint(x: previous.frame.minX + 24, y: previous.frame.maxY - 24))
        }
        let controller = NSWindowController(window: window)
        controllers[id] = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        registry.activate(id)
        registered.startSession()
        return id
    }

    public func focus(_ id: UUID) {
        guard let window = controllers[id]?.window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        registry.activate(id)
    }

    public func close(_ id: UUID) { controllers[id]?.window?.close() }

    private func window(for session: SessionViewModel) -> NSWindow? {
        for (id, controller) in controllers {
            if registry.session(for: id) === session {
                return controller.window
            }
        }
        return nil
    }

    public func isFloating(for session: SessionViewModel) -> Bool {
        guard let window = window(for: session) else { return false }
        return window.level == .floating
    }

    @discardableResult
    public func toggleFloating(for session: SessionViewModel) -> Bool {
        guard let window = window(for: session) else { return false }
        let nextFloating = window.level != .floating
        window.level = nextFloating ? .floating : .normal
        return nextFloating
    }

    public func fitWindowToRemoteAspectRatio(for session: SessionViewModel, remoteSize: CGSize) {
        guard let window = window(for: session),
              remoteSize.width > 0, remoteSize.height > 0 else { return }
        let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let targetFrame = Self.calculateAspectRatioFrame(
            currentFrame: window.frame,
            remoteSize: remoteSize,
            visibleScreenFrame: screenFrame,
            minSize: window.minSize
        )
        window.setFrame(targetFrame, display: true, animate: true)
    }

    /// Computes a new window frame matching the remote desktop's aspect ratio, centered on `currentFrame` and clamped to `visibleScreenFrame`.
    public static func calculateAspectRatioFrame(
        currentFrame: CGRect,
        remoteSize: CGSize,
        visibleScreenFrame: CGRect,
        minSize: CGSize = CGSize(width: 800, height: 560)
    ) -> CGRect {
        guard remoteSize.width > 0, remoteSize.height > 0 else { return currentFrame }
        let aspect = remoteSize.width / remoteSize.height
        let maxW = max(minSize.width, visibleScreenFrame.width)
        let maxH = max(minSize.height, visibleScreenFrame.height)

        var newW = min(max(currentFrame.width, minSize.width), maxW)
        var newH = newW / aspect

        if newH < minSize.height {
            newH = minSize.height
            newW = min(newH * aspect, maxW)
        }
        if newH > maxH {
            newH = maxH
            newW = max(minSize.width, newH * aspect)
        }

        var originX = currentFrame.midX - newW / 2.0
        var originY = currentFrame.midY - newH / 2.0

        originX = min(max(originX, visibleScreenFrame.minX), visibleScreenFrame.maxX - newW)
        originY = min(max(originY, visibleScreenFrame.minY), visibleScreenFrame.maxY - newH)

        return CGRect(x: originX.rounded(), y: originY.rounded(), width: newW.rounded(), height: newH.rounded())
    }

    public func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = controllers.first(where: { $0.value.window === window })?.key else { return }
        registry.activate(id)
    }

    public func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = controllers.first(where: { $0.value.window === window })?.key else { return }
        registry.session(for: id)?.setForegroundSession(false)
    }

    public func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = controllers.first(where: { $0.value.window === window })?.key else { return }
        if let session = registry.remove(id) {
            session.endSession()
            session.client.disconnect()
            session.rdpClient?.disconnect()
        }
        controllers.removeValue(forKey: id)
    }
}

private struct SessionWindowContent: View {
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    let session: SessionViewModel
    let close: () -> Void

    var body: some View {
        RemoteDesktopView(viewModel: session, managesSessionLifecycle: false, onDisconnect: {
            session.requestDisconnect()
            close()
        })
            .environment(\.locale, languageSettings.locale)
            .tint(.blue)
    }
}
#endif
