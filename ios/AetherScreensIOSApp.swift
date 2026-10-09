import SwiftUI
import AetherScreensCore
import AppIntents

struct AetherScreensIOSIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [AetherScreensCoreIntents.self] }
}

struct AetherScreensIOSShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ConnectSavedComputerIntent(),
                    phrases: ["Connect to \(\.$computer) with \(.applicationName)",
                              "Connect to a computer with \(.applicationName)"],
                    shortTitle: "Connect to Computer", systemImageName: "desktopcomputer")
    }
}

@main
struct AetherScreensIOSApp: App {
    var body: some Scene {
        WindowGroup {
            DeviceListView()
                .tint(.blue)
                .background(ExternalDisplayRegistrationView().frame(width: 0, height: 0))
        }
    }
}

@MainActor
final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene,
              session.role == .windowExternalDisplayNonInteractive else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: ExternalDesktopPresentationView())
        window.backgroundColor = .black
        window.isHidden = false
        self.window = window
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }
}

private struct ExternalDisplayRegistrationView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        ExternalDisplayRegistrationController()
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

private final class ExternalDisplayRegistrationController: UIViewController {
    private var accessoryRegistration: AnyObject?
    override func viewDidLoad() {
        super.viewDidLoad()
        view.isUserInteractionEnabled = false
        if #available(iOS 27.0, *) {
            let configuration = UISceneConfiguration(name: "External Desktop", sessionRole: .windowExternalDisplayNonInteractive)
            configuration.delegateClass = ExternalDisplaySceneDelegate.self
            let registration = registerSceneAccessory(.externalNonInteractive(sceneConfiguration: configuration))
            registration.isEnabled = true
            accessoryRegistration = registration
        }
    }
}
