import SwiftUI
import AetherScreensCore
#if os(macOS)
import AppKit
#endif

@main
struct AetherScreensMainApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(ShortcutApplicationDelegate.self) private var delegate
    #endif
    var body: some Scene {
        WindowGroup(id: "library") {
            Group {
                #if os(macOS)
                ShortcutLibraryHostView()
                #else
                ForegroundLibraryRootView()
                #endif
            }
                .tint(.blue)
                #if os(macOS)
                .frame(minWidth: 800, minHeight: 520)
                #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .commands {
            SidebarCommands()
        }
        #endif
    }
}

#if os(macOS)
@MainActor
enum ShortcutLibraryWindowBridge {
    static var openLibrary: (() -> Void)?
    static var libraryConsumers = Set<UUID>()
    private static var pending = false

    static func request() { pending = true; showIfActive() }

    static func showIfActive() {
        guard NSApp.isActive, pending else { return }
        if !libraryConsumers.isEmpty { pending = false; return }
        guard let openLibrary else { return }
        pending = false
        openLibrary()
    }
}

@MainActor
final class ShortcutApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidBecomeActive(_ notification: Notification) {
        ShortcutLibraryWindowBridge.showIfActive()
    }
}

@MainActor
private struct ShortcutLibraryHostView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var consumerID = UUID()
    var body: some View {
        ForegroundLibraryRootView()
            .onAppear {
                ShortcutLibraryWindowBridge.libraryConsumers.insert(consumerID)
                ShortcutLibraryWindowBridge.openLibrary = { openWindow(id: "library") }
                ShortcutLibraryWindowBridge.showIfActive()
            }
            .onDisappear { ShortcutLibraryWindowBridge.libraryConsumers.remove(consumerID) }
    }
}
#endif
