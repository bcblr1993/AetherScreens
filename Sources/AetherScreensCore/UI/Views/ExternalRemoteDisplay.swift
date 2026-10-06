#if os(iOS) && !targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

/// Register on the session's own controller. UIKit manages external-display
/// availability and disconnects its scene when this controller leaves the UI.
@available(iOS 27.0, *)
struct ExternalRemoteDisplayRegistration: UIViewControllerRepresentable {
    let session: SessionViewModel

    func makeUIViewController(context: Context) -> RegistrationController {
        RegistrationController(session: session)
    }

    func updateUIViewController(_ controller: RegistrationController, context: Context) {
        controller.updateEnabledState()
    }

    static func dismantleUIViewController(_ controller: RegistrationController, coordinator: ()) {
        controller.unregister()
    }

    final class RegistrationController: UIViewController {
        private let session: SessionViewModel
        private var registration: UISceneAccessoryRegistration?

        init(session: SessionViewModel) {
            self.session = session
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("Use init(session:)") }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
            let configuration = UISceneConfiguration()
            configuration.delegateClass = ExternalRemoteDisplaySceneDelegate.self
            let accessory = UISceneAccessory.externalNonInteractive(
                sceneConfiguration: configuration, userInfo: AccessoryContext(session: session))
            let registration = registerSceneAccessory(accessory)
            registration.isEnabled = false
            self.registration = registration
            session.externalDisplayMirror.onEnabledChanged = { [weak self] _ in self?.updateEnabledState() }
        }

        override func updateProperties() {
            super.updateProperties()
            // Reading isAvailable here participates in UIKit observation tracking.
            session.externalDisplayMirror.updateAvailability(registration?.isAvailable == true)
            updateEnabledState()
        }

        func updateEnabledState() {
            registration?.isEnabled = session.externalDisplayMirror.isMirroring
        }

        func unregister() {
            session.externalDisplayMirror.updateAvailability(false)
            session.externalDisplayMirror.onEnabledChanged = nil
            if let registration { unregisterSceneAccessory(registration) }
            registration = nil
        }
    }

    final class AccessoryContext: NSObject {
        weak var session: SessionViewModel?
        init(session: SessionViewModel) { self.session = session }
    }
}

@available(iOS 27.0, *)
final class ExternalRemoteDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private weak var mirror: RemoteDisplayMirror?
    private var presentationID: UUID?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard session.role == .windowExternalDisplayNonInteractive,
              let windowScene = scene as? UIWindowScene,
              let context = connectionOptions.sceneAccessoryUserInfo as? ExternalRemoteDisplayRegistration.AccessoryContext,
              let model = context.session,
              let presentation = model.externalDisplayMirror.beginPresentation(framebuffer: model.client.framebuffer) else { return }
        mirror = model.externalDisplayMirror
        presentationID = presentation.id
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: ExternalRemoteDisplayContent(
            session: model, mirror: model.externalDisplayMirror, renderer: presentation.renderer))
        window.backgroundColor = .black
        self.window = window
        window.isHidden = false
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        if let presentationID { mirror?.endPresentation(id: presentationID) }
        presentationID = nil
        mirror = nil
    }
}

@available(iOS 27.0, *)
private struct ExternalRemoteDisplayContent: View {
    @ObservedObject var session: SessionViewModel
    @ObservedObject var mirror: RemoteDisplayMirror
    let renderer: MetalScreenRenderer?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if mirror.isMirroring && session.sessionState == .connected && session.isForegroundSession {
                    let crop = session.activeCropRect
                    let width = crop?.width ?? CGFloat(session.client.framebuffer.width)
                    let height = crop?.height ?? CGFloat(session.client.framebuffer.height)
                    if width > 0 && height > 0 {
                        let scale = min(geometry.size.width / width, geometry.size.height / height)
                        Group {
                            if let renderer {
                                MetalScreenView(renderer: renderer, sourceRect: crop)
                            } else if let image = session.currentImage {
                                Image(decorative: crop.flatMap { image.cropping(to: $0) } ?? image, scale: 1)
                                    .resizable()
                            }
                        }
                        .frame(width: width * scale, height: height * scale)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
