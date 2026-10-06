import SwiftUI

/// Entity queries can launch the host before it has an active scene. Keep
/// discovery, preference recovery and the credential store out of that path.
@MainActor
public struct ForegroundLibraryRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: DeviceListViewModel?
    @State private var incomingURLs: [URL] = []

    public init() {}

    public var body: some View {
        Group {
            if let viewModel {
                DeviceListView(viewModel: viewModel, incomingURLs: $incomingURLs)
            } else {
                Color.clear
            }
        }
        .onAppear(perform: prepareActiveLibrary)
        .onChange(of: scenePhase) { _, _ in prepareActiveLibrary() }
        .onOpenURL { url in
            // Preserve cold URL opens in memory until the library is active.
            if incomingURLs.count < 16 { incomingURLs.append(url) }
            prepareActiveLibrary()
        }
    }

    private func prepareActiveLibrary() {
        guard scenePhase == .active, viewModel == nil else { return }
        SessionLiveActivityController.shared.applicationWillEnterForeground()
        SessionLiveActivityController.shared.reconcileAfterLaunch()
        viewModel = DeviceListViewModel(shortcutCatalogStore: .shared,
                                       widgetCatalogStore: WidgetCatalogStore.standardIfConfigured())
    }
}
