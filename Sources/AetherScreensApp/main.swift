import SwiftUI
import AetherScreensCore

@main
struct AetherScreensMainApp: App {
    var body: some Scene {
        WindowGroup {
            DeviceListView()
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
