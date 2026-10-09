import SwiftUI
import AetherScreensCore
import AppIntents

struct AetherScreensMacIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [AetherScreensCoreIntents.self] }
}

struct AetherScreensMacShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ConnectSavedComputerIntent(),
                    phrases: ["Connect to \(\.$computer) with \(.applicationName)",
                              "Connect to a computer with \(.applicationName)"],
                    shortTitle: "Connect to Computer", systemImageName: "desktopcomputer")
    }
}

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
