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
@MainActor
struct AetherScreensMainApp: App {
    #if os(macOS)
    @StateObject private var appUpdater = AppUpdater()
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    @ObservedObject private var sessionRegistry = SessionRegistry.shared
    #endif
    var body: some Scene {
        WindowGroup {
            DeviceListView()
                .tint(.blue)
                #if os(macOS)
                .frame(minWidth: 800, minHeight: 520)
                // Deliver connection links and Shortcuts to the open library instead of a new window.
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .commands {
            SidebarCommands()
            CommandGroup(after: .appInfo) {
                Button(AppLocalization.string("Check for Updates…")) { appUpdater.checkForUpdates() }
                    .disabled(!appUpdater.canCheckForUpdates)
            }
        }
        #endif

        #if os(macOS)
        MenuBarExtra("AetherScreens", systemImage: "display.2") {
            MenuBarQuickConnectView()
        }
        #endif
    }
}

#if os(macOS)
@MainActor
private struct MenuBarQuickConnectView: View {
    @ObservedObject private var sessionRegistry = SessionRegistry.shared
    @ObservedObject private var appLockService = AppLockService.shared

    private var savedDevices: [RemoteDevice] {
        DeviceStore.shared.devices.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite && !rhs.isFavorite }
            return (lhs.lastConnected ?? .distantPast) > (rhs.lastConnected ?? .distantPast)
        }
    }

    var body: some View {
        if appLockService.blocksAccess {
            Text(AppLocalization.string("AetherScreens is Locked"))
        } else {
            if !sessionRegistry.sessions.isEmpty {
                Section(AppLocalization.string("Open Sessions")) {
                    ForEach(sessionRegistry.sessions) { entry in
                        Button {
                            NSApplication.shared.activate(ignoringOtherApps: true)
                            SessionWindowManager.shared.focus(entry.id)
                        } label: {
                            Label(entry.title, systemImage: "display")
                        }
                    }
                }
                Divider()
            }

            let computers = Array(savedDevices.prefix(10))
            if computers.isEmpty {
                Text(AppLocalization.string("No saved computers yet"))
            } else {
                Section(AppLocalization.string("Quick Connect")) {
                    ForEach(computers) { device in
                        Button {
                            NSApplication.shared.activate(ignoringOtherApps: true)
                            let password = DeviceStore.shared.getPassword(for: device)
                            let session = SessionViewModel(device: device, password: password)
                            SessionWindowManager.shared.open(session)
                        } label: {
                            Label(
                                "\(device.name) (\(device.remoteProtocol.rawValue))",
                                systemImage: device.deviceType.systemIcon
                            )
                        }
                    }
                }
            }
        }
        Divider()
        Button(AppLocalization.string("Show AetherScreens Library")) {
            NSApplication.shared.activate(ignoringOtherApps: true)
            if let window = NSApplication.shared.windows.first {
                window.makeKeyAndOrderFront(nil)
            }
        }
        .keyboardShortcut("0", modifiers: [.command])
    }
}
#endif
