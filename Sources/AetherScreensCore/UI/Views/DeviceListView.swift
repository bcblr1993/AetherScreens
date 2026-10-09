import SwiftUI
import UniformTypeIdentifiers

/// Sidebar navigation category for macOS and iPadOS
public enum DeviceCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "All Computers"
    case nearby = "Nearby (Bonjour)"
    case tailscale = "Tailscale Nodes"
    case mac = "Macs"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .all: return "display.2"
        case .nearby: return "dot.radiowaves.left.and.right"
        case .tailscale: return "point.3.connected.trianglepath.dotted"
        case .mac: return "apple.logo"
        }
    }
}

/// Main dashboard displaying remote machines, Bonjour nearby discovery, Tailscale sync, and quick connect.
/// Fully optimized for both iOS (iPhone & iPad) and macOS (Apple Silicon Mac).
public struct DeviceListView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    @StateObject private var viewModel = DeviceListViewModel()
    @State private var selectedCategory: DeviceCategory = .all
    @State private var showingAddSheet = false
    @State private var showingQuickConnectSheet = false
    @State private var pendingQuickSession: SessionViewModel?
    @State private var showingSettingsSheet = false
    @State private var activeSessionVM: SessionViewModel?
    @State private var editingDevice: RemoteDevice?
    @State private var showingLogs = false
    @State private var pendingConnectionLinks: [ConnectionLink.Resolved] = []
    @ObservedObject private var sessionRegistry = SessionRegistry.shared

    private let columns = [
        GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 16)
    ]

    public init() {}

    public var body: some View {
        Group {
        #if os(macOS)
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
        } detail: {
            mainGridView
                .navigationTitle(AppLocalization.string(selectedCategory.rawValue))
        }
        .onChange(of: sessionRegistry.sessions.count) { _, _ in viewModel.reload() }
        .sheet(item: $editingDevice, onDismiss: openPendingConnectionLink) { dev in
            EditDeviceSheet(device: dev, viewModel: viewModel)
        }
        .sheet(isPresented: $showingLogs, onDismiss: openPendingConnectionLink) {
            DiagnosticLogView()
        }
        .sheet(isPresented: $showingAddSheet, onDismiss: openPendingConnectionLink) {
            AddDeviceSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showingQuickConnectSheet, onDismiss: openPendingQuickSession) {
            quickConnectSheet
        }
        .sheet(isPresented: $showingSettingsSheet, onDismiss: openPendingConnectionLink) {
            TailscaleSettingsSheet(viewModel: viewModel)
        }
        #else
        NavigationStack {
            mainGridView
                .navigationTitle(AppLocalization.string("AetherScreens"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("AetherScreens")
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .accessibilityIdentifier("library-title")
                    }
                }
                .fullScreenCover(item: $activeSessionVM, onDismiss: { viewModel.reload(); openPendingConnectionLink() }) { sessionVM in
                    RemoteDesktopView(viewModel: sessionVM, managesSessionLifecycle: false,
                                      onDisconnect: { closeMobileSession(sessionVM) },
                                      onReturnToLibrary: {
                                          sessionRegistry.returnToLibrary()
                                          activeSessionVM = nil
                                      })
                }
                .sheet(item: $editingDevice, onDismiss: openPendingConnectionLink) { dev in
                    EditDeviceSheet(device: dev, viewModel: viewModel)
                }
                .sheet(isPresented: $showingLogs, onDismiss: openPendingConnectionLink) {
                    DiagnosticLogView()
                }
                .sheet(isPresented: $showingAddSheet, onDismiss: openPendingConnectionLink) {
                    AddDeviceSheet(viewModel: viewModel)
                }
                .sheet(isPresented: $showingQuickConnectSheet, onDismiss: openPendingQuickSession) {
                    quickConnectSheet
                }
                .sheet(isPresented: $showingSettingsSheet, onDismiss: openPendingConnectionLink) {
                    TailscaleSettingsSheet(viewModel: viewModel)
                }
        }
        #endif
        }
        .environment(\.locale, languageSettings.locale)
        .onOpenURL(perform: receiveConnectionLink)
        .onReceive(SavedComputerIntentInbox.shared.$revision) { _ in
            Task { @MainActor in
                for id in SavedComputerIntentInbox.shared.drain() {
                    receiveConnectionLink(ConnectionLink.savedURL(for: id))
                }
            }
        }
    }

    // MARK: - Sidebar (macOS)

    #if os(macOS)
    private var sidebarContent: some View {
        List(DeviceCategory.allCases, selection: $selectedCategory) { category in
            HStack {
                Label(AppLocalization.string(category.rawValue), systemImage: category.icon)
                Spacer()
                if category == .nearby && !viewModel.filteredNearbyMacs.isEmpty {
                    Text("\(viewModel.filteredNearbyMacs.count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                }
            }
            .tag(category)
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showingSettingsSheet = true
                } label: {
                    Image(systemName: "gear")
                }
            }
        }
    }
    #endif

    // MARK: - Main Grid View

    private var mainGridView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                dashboardHeader
                // Error Notification Banner
                if let err = viewModel.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(AppLocalization.message(err))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            viewModel.errorMessage = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(ControlPressStyle())
                        .accessibilityLabel(AppLocalization.string("Dismiss"))
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                }

                // Success / Status Notice Banner
                if let notice = viewModel.statusNotice {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(AppLocalization.message(notice))
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                        Spacer()
                        Button {
                            viewModel.statusNotice = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(ControlPressStyle())
                        .accessibilityLabel(AppLocalization.string("Dismiss"))
                    }
                    .padding(12)
                    .background(Color.green.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                }

                // Discovered Nearby Macs (Bonjour) Section
                if !viewModel.filteredNearbyMacs.isEmpty && (selectedCategory == .all || selectedCategory == .nearby) {
                    nearbyBonjourSection
                }

                // Configured Saved Computers Grid
                let devices = displayedDevices
                if devices.isEmpty && !showsNearbyDevices {
                    emptyStateView
                } else if !devices.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        if !viewModel.filteredNearbyMacs.isEmpty {
                            Text(AppLocalization.string("Your computers"))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 20)
                        }

                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(devices) { device in
                                DeviceCardView(
                                    device: device,
                                    onConnect: { openSession(for: device) },
                                    onWake: { viewModel.wakeDevice(device) }
                                )
                                .transition(.opacity)
                                .contextMenu {
                                    Button {
                                        openSession(for: device)
                                    } label: {
                                        Label(AppLocalization.string("Connect"), systemImage: "arrow.up.right.video")
                                    }

                                    #if os(macOS)
                                    Button {
                                        let session = SessionViewModel(device: device, password: DeviceStore.shared.getPassword(for: device))
                                        SessionWindowManager.shared.open(session, reuseExisting: false)
                                    } label: {
                                        Label(AppLocalization.string("Open in New Window"), systemImage: "macwindow.badge.plus")
                                    }
                                    #endif

                                    Button {
                                        editingDevice = device
                                    } label: {
                                        Label(AppLocalization.string("Edit Computer..."), systemImage: "pencil")
                                    }

                                    Button {
                                        let link = ConnectionLink.savedURL(for: device.id).absoluteString
                                        #if canImport(UIKit)
                                        UIPasteboard.general.string = link
                                        #elseif canImport(AppKit)
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(link, forType: .string)
                                        #endif
                                        viewModel.statusNotice = "Connection link copied"
                                    } label: {
                                        Label(AppLocalization.string("Copy Connection Link"), systemImage: "link")
                                    }

                                    if let mac = device.macAddress, !mac.isEmpty {
                                        Button {
                                            viewModel.wakeDevice(device)
                                        } label: {
                                            Label(AppLocalization.string("Wake Mac (WOL)"), systemImage: "bolt.fill")
                                        }
                                    }

                                    Divider()

                                    Button(role: .destructive) {
                                        viewModel.deleteDevice(device)
                                    } label: {
                                        Label(AppLocalization.string("Delete"), systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .animation(libraryTransitionAnimation, value: selectedCategory)
                        .animation(libraryTransitionAnimation, value: viewModel.devices.map(\.id))
                        .padding(.horizontal, 20)
                    }
                }
            }
            .padding(.vertical, 24)
        }
        .background(dashboardBackground)
        .searchable(text: $viewModel.searchText, prompt: AppLocalization.string("Search computers or Tailscale IP"))
        .refreshable {
            await viewModel.syncTailscale()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                #if os(macOS)
                libraryUtilityActions
                    .labelStyle(.iconOnly)
                Menu {
                    ForEach(sessionRegistry.sessions) { entry in
                        Button(entry.title) {
                            SessionWindowManager.shared.focus(entry.id)
                        }
                    }
                } label: {
                    Label(AppLocalization.string("Open Sessions"), systemImage: "display.2")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel(AppLocalization.string("Open Sessions"))
                .help(AppLocalization.string("Open Sessions"))
                .disabled(sessionRegistry.sessions.isEmpty)
                #else
                Menu {
                    ForEach(sessionRegistry.sessions) { entry in
                        Button(entry.title) { activeSessionVM = sessionRegistry.activate(entry.id) }
                            .accessibilityIdentifier("open-session-\(entry.number)")
                    }
                } label: {
                    Label(AppLocalization.string("Open Sessions"), systemImage: "display.2")
                }
                .accessibilityLabel(AppLocalization.string("Open Sessions"))
                .accessibilityIdentifier("open-sessions")
                .disabled(sessionRegistry.sessions.isEmpty)
                #endif

                // Temporary or optionally saved connection
                Button {
                    showingQuickConnectSheet = true
                } label: {
                    Image(systemName: "bolt.horizontal.circle")
                }
                .help(AppLocalization.string("Quick Connect"))
                .accessibilityLabel(AppLocalization.string("Quick Connect"))

                // Add Computer Button
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .help(AppLocalization.string("Add Computer Manually"))
                .accessibilityLabel(AppLocalization.string("Add Computer"))
            }

            #if canImport(UIKit)
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button {
                        showingSettingsSheet = true
                    } label: {
                        Label(AppLocalization.string("Settings"), systemImage: "gear")
                    }
                    Divider()
                    libraryUtilityActions
                } label: {
                    Image(systemName: "gear")
                }
                .accessibilityLabel(AppLocalization.string("More Actions"))
            }
            #endif
        }
    }

    private var libraryTransitionAnimation: Animation? {
        guard !reduceMotion, viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return .smooth(duration: 0.22)
    }

    @ViewBuilder
    private var libraryUtilityActions: some View {
        Button {
            showingLogs = true
        } label: {
            Label(AppLocalization.string("Diagnostic Logs"), systemImage: "list.bullet.rectangle")
        }
        .help(AppLocalization.string("View Diagnostic Logs"))
        .accessibilityLabel(AppLocalization.string("Diagnostic Logs"))

        Button {
            Task { await viewModel.syncTailscale() }
        } label: {
            Label(AppLocalization.string(viewModel.isSyncingTailscale ? "Syncing…" : "Sync Tailscale Devices"), systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(viewModel.isSyncingTailscale)
        .help(AppLocalization.string("Sync Tailscale Online Nodes"))
        .accessibilityLabel(AppLocalization.string("Sync Tailscale Devices"))
    }

    // MARK: - Nearby Bonjour Macs Section

    private var dashboardHeader: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(AppLocalization.string("WORKSPACE"))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.secondary)
                Text(AppLocalization.string("Your screens"))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .tracking(-0.7)
                Text(AppLocalization.string("Connect to your computers from anywhere."))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(AppLocalization.format(viewModel.filteredDevices.count == 1 ? "%d computer" : "%d computers", viewModel.filteredDevices.count))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private var nearbyBonjourSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundColor(.accentColor)
                Text(AppLocalization.string("Nearby Macs (Local Wi-Fi)"))
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Text(AppLocalization.format("%d discovered", viewModel.filteredNearbyMacs.count))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.filteredNearbyMacs) { discovered in
                        Button {
                            viewModel.addDiscoveredMac(discovered)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 20))
                                    .foregroundColor(.primary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(discovered.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Text(discovered.host)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .frame(width: 170, alignment: .leading)

                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.accentColor)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(width: 250)
                            .background(Color.accentColor.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(AppLocalization.format("Add %@", discovered.name))
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var displayedDevices: [RemoteDevice] {
        let base = viewModel.filteredDevices
        switch selectedCategory {
        case .all:
            return base
        case .nearby:
            return []
        case .tailscale:
            return base.filter { $0.isTailscaleNode }
        case .mac:
            return base.filter { $0.deviceType == .mac }
        }
    }

    private var showsNearbyDevices: Bool {
        !viewModel.filteredNearbyMacs.isEmpty && (selectedCategory == .all || selectedCategory == .nearby)
    }

    private var dashboardBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }

    private func openSession(for device: RemoteDevice) {
        let password = DeviceStore.shared.getPassword(for: device)
        let session = SessionViewModel(device: device, password: password)
        presentSession(session)
    }

    private var quickConnectSheet: some View {
        AddDeviceSheet(viewModel: viewModel) { request, saveComputer in
            pendingQuickSession = try viewModel.prepareQuickSession(request, saveComputer: saveComputer)
        }
    }

    private func openPendingQuickSession() {
        if let session = pendingQuickSession {
            pendingQuickSession = nil
            presentSession(session)
        }
        openPendingConnectionLink()
    }

    private func receiveConnectionLink(_ url: URL) {
        do {
            let link = try ConnectionLink(url: url)
            viewModel.reload()
            let resolved = try link.resolve(devices: viewModel.devices) { DeviceStore.shared.getPassword(for: $0) }
            #if !os(macOS)
            if !resolved.requiresIndependentSession,
               let existing = sessionRegistry.reusableEntry(for: resolved.device.id),
               activeSessionVM === existing.viewModel {
                // The requested saved connection is already presented; do not queue a reopening.
                return
            }
            #endif
            pendingConnectionLinks.append(resolved)
            openPendingConnectionLink()
        } catch let error as ConnectionLink.Failure {
            viewModel.errorMessage = error.messageKey
        } catch {
            viewModel.errorMessage = ConnectionLink.Failure.invalid.messageKey
        }
    }

    private func openPendingConnectionLink() {
        guard !showingAddSheet, !showingQuickConnectSheet, !showingSettingsSheet,
              !showingLogs, editingDevice == nil, pendingQuickSession == nil,
              !pendingConnectionLinks.isEmpty else { return }
        #if !os(macOS)
        guard activeSessionVM == nil else { return }
        #endif
        let resolved = pendingConnectionLinks.removeFirst()
        let session = SessionViewModel(device: resolved.device, password: resolved.password, isTemporary: resolved.isTemporary)
        if let observe = resolved.observeOnly { session.isObserveOnly = observe }
        #if os(macOS)
        SessionWindowManager.shared.open(session, reuseExisting: !resolved.requiresIndependentSession)
        openPendingConnectionLink()
        #else
        presentSession(session, reuseExisting: !resolved.requiresIndependentSession)
        #endif
    }

    private func presentSession(_ session: SessionViewModel, reuseExisting: Bool = true) {
        #if os(macOS)
        SessionWindowManager.shared.open(session)
        #else
        let id = sessionRegistry.register(session, reuseExisting: reuseExisting)
        activeSessionVM = sessionRegistry.activate(id)
        if activeSessionVM === session { session.startSession() }
        #endif
    }

    #if !os(macOS)
    private func closeMobileSession(_ session: SessionViewModel) {
        if let entry = sessionRegistry.sessions.first(where: { $0.viewModel === session }) {
            sessionRegistry.close(entry.id)
        }
        activeSessionVM = nil
    }
    #endif

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "display.2")
                .font(.system(size: 38, weight: .ultraLight))
                .foregroundStyle(.secondary)
                .frame(width: 88, height: 88)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))

            Text(AppLocalization.string(viewModel.normalizedSearchQuery.isEmpty ? "No computers here yet" : "No matching computers"))
                .font(.system(size: 20, weight: .semibold))

            Text(AppLocalization.string(viewModel.normalizedSearchQuery.isEmpty ? "Add a computer to start a remote session. You can also sync devices from your tailnet." : "Try a different name or address."))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if viewModel.normalizedSearchQuery.isEmpty && selectedCategory == .all {
                Button {
                    showingAddSheet = true
                } label: {
                    Label(AppLocalization.string("Add computer"), systemImage: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 10)
            }
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

/// Settings sheet for configuring Tailscale API credentials
public struct TailscaleSettingsSheet: View {
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    @ObservedObject public var viewModel: DeviceListViewModel
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(AppLocalization.string("Language"))) {
                    Picker(AppLocalization.string("App Language"), selection: $languageSettings.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .accessibilityIdentifier("app-language")
                }
                Section(
                    header: Text(AppLocalization.string("Tailscale API Credentials")),
                    footer: Text(AppLocalization.string("Generate an API Access Token or OAuth Client in your Tailscale Admin Console (Settings > Keys). This allows AetherScreens to automatically discover your online devices."))
                ) {
                    SecureField(AppLocalization.string("API Access Token (tskey-api-...)"), text: $viewModel.tailscaleApiKey)
                        .autocorrectionDisabled()
                        #if canImport(UIKit)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.asciiCapable)
                        #endif
                    TextField(AppLocalization.string("Tailnet Name (Optional, e.g. example.com)"), text: $viewModel.tailnetName)
                        .autocorrectionDisabled()
                        #if canImport(UIKit)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                }

                Section(header: Text(AppLocalization.string("Secure Connection"))) {
                    NavigationLink {
                        SSHKeyLibraryView(viewModel: viewModel)
                    } label: {
                        Label(AppLocalization.string("SSH Keys"), systemImage: "key")
                    }
                    .accessibilityIdentifier("ssh-key-library")
                }

                Section(header: Text(AppLocalization.string("About macOS Screen Sharing"))) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppLocalization.string("1. Open System Settings on Mac > General > Sharing."))
                            .font(.system(size: 13))
                        Text(AppLocalization.string("2. Turn on Screen Sharing."))
                            .font(.system(size: 13))
                        Text(AppLocalization.string("3. Use your Mac account, or enable password access for VNC viewers in Computer Settings."))
                            .font(.system(size: 13))
                        Text(AppLocalization.string("4. For connections across networks, run Tailscale on both devices."))
                            .font(.system(size: 13))
                    }
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(AppLocalization.string("Settings"))
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("Done")) {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(width: 540, height: 480)
        #endif
    }
}

/// User-triggered vault reads keep private data out of SwiftUI body evaluation.
private struct SSHKeyLibraryView: View {
    @ObservedObject var viewModel: DeviceListViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var keys: [DeviceListViewModel.ManagedSSHKey] = []
    @State private var errorMessage: String?
    @State private var importing = false
    @State private var encryptedImport: EncryptedSSHKeyImport?
    @State private var exporting = false
    @State private var exportDocument: SSHPrivateKeyDocument?
    @State private var pendingExport: DeviceListViewModel.ManagedSSHKey?
    @State private var pendingRemoval: DeviceListViewModel.ManagedSSHKey?
    @State private var pendingRename: DeviceListViewModel.ManagedSSHKey?
    @State private var keyName = ""
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                Button(AppLocalization.string("Import Private Key")) { importing = true }
                    .accessibilityIdentifier("ssh-library-import")
                    .sheet(item: $encryptedImport) { request in
                        SSHKeyUnlockSheet(request: request) { normalized in
                            try viewModel.importManagedSSHKey(normalized)
                            reload()
                        }
                    }
                HStack {
                    Text(AppLocalization.string("Paste Private Key"))
                    Spacer()
                    PasteButton(payloadType: String.self) { values in
                        do {
                            guard let value = values.first else { throw SSHPrivateKey.Failure.invalid }
                            guard value.utf8.count <= SSHPrivateKey.maximumSize else { throw SSHPrivateKey.Failure.tooLarge }
                            try importKey(Data(value.utf8))
                            reload()
                        } catch { show(error) }
                    }
                    .fixedSize()
                    .accessibilityIdentifier("ssh-library-paste")
                    .accessibilityLabel(AppLocalization.string("Paste Private Key"))
                }
                .accessibilityElement(children: .contain)
            } footer: {
                Text(AppLocalization.string("Import an Ed25519 or ECDSA key, including encrypted ECDSA PKCS#8. Private keys stay in Keychain."))
            }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                    Button(AppLocalization.string("Retry")) { reload() }
                }
            }
            Section(header: Text(AppLocalization.string("Saved Private Keys"))) {
                if keys.isEmpty && errorMessage == nil {
                    Text(AppLocalization.string("No saved private keys"))
                        .foregroundStyle(.secondary)
                }
                ForEach(keys) { key in
                    VStack(alignment: .leading, spacing: 8) {
                        if let name = key.name { Text(name).font(.headline) }
                        if let fingerprint = key.fingerprint {
                            Text(fingerprint).font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .accessibilityIdentifier("ssh-library-fingerprint-" + key.id.uuidString)
                        }
                        if let problem = key.problem { Text(problem).foregroundStyle(.red) }
                        Text(key.computers.isEmpty
                             ? AppLocalization.string("Not used by a saved computer")
                             : key.computers.joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                        Button(AppLocalization.string("Rename")) {
                            keyName = key.name ?? ""
                            pendingRename = key
                        }
                        .accessibilityIdentifier("ssh-library-rename-" + key.id.uuidString)
                        Button(AppLocalization.string("Export Private Key")) { pendingExport = key }
                            .disabled(key.fingerprint == nil)
                            .accessibilityIdentifier("ssh-library-export-" + key.id.uuidString)
                        Button(AppLocalization.string("Delete"), role: .destructive) { pendingRemoval = key }
                            .disabled(!key.computers.isEmpty)
                            .accessibilityIdentifier("ssh-library-delete-" + key.id.uuidString)
                    }
                    .buttonStyle(.borderless)
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(AppLocalization.string("SSH Keys"))
        .onAppear { reload() }
        .alert(AppLocalization.string("Key Name"), isPresented: Binding(
            get: { pendingRename != nil }, set: { if !$0 { pendingRename = nil } })) {
                TextField(AppLocalization.string("Key Name"), text: $keyName)
                    .accessibilityIdentifier("ssh-library-key-name")
                Button(AppLocalization.string("Save")) {
                    guard let key = pendingRename else { return }
                    pendingRename = nil
                    do { try viewModel.renameManagedSSHKey(key.id, name: keyName); reload() }
                    catch { show(error) }
                }
                Button(AppLocalization.string("Cancel"), role: .cancel) { pendingRename = nil }
            }
        .confirmationDialog(AppLocalization.string("Delete Private Key?"),
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible) {
                Button(AppLocalization.string("Delete"), role: .destructive) {
                    guard let key = pendingRemoval else { return }
                    pendingRemoval = nil
                    do { try viewModel.removeManagedSSHKey(key.id); reload() }
                    catch { show(error) }
                }
                Button(AppLocalization.string("Cancel"), role: .cancel) { pendingRemoval = nil }
            }
        .confirmationDialog(AppLocalization.string("Export Private Key?"),
            isPresented: Binding(get: { pendingExport != nil }, set: { if !$0 { pendingExport = nil } }),
            titleVisibility: .visible) {
                Button(AppLocalization.string("Export")) {
                    guard let key = pendingExport, let fingerprint = key.fingerprint else { return }
                    pendingExport = nil
                    do {
                        let data = try viewModel.exportManagedSSHKey(key.id, expectedFingerprint: fingerprint)
                        exportDocument = try SSHPrivateKeyDocument(data: data)
                        exporting = true
                    } catch { exportDocument = nil; show(error) }
                }
                Button(AppLocalization.string("Cancel"), role: .cancel) { pendingExport = nil }
            } message: {
                Text(AppLocalization.string("The exported file contains your unencrypted private key. Choose a trusted destination."))
            }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentTypes: [.plainText],
                      defaultFilename: "ssh-private-key", onCompletion: { result in
            exportDocument = nil
            if case .failure(let error) = result {
                if let cocoa = error as? CocoaError, cocoa.code == .userCancelled { return }
                publishChange { errorMessage = AppLocalization.string("Could not export the private key. Try another destination.") }
            }
        }, onCancellation: { exportDocument = nil })
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let file = try FileHandle(forReadingFrom: url)
                defer { try? file.close() }
                let data = try file.read(upToCount: SSHPrivateKey.maximumSize + 1) ?? Data()
                try importKey(data)
                reload()
            } catch {
                if let cocoa = error as? CocoaError, cocoa.code == .userCancelled { return }
                show(error)
            }
        }
    }

    private func importKey(_ data: Data) throws {
        if let request = try EncryptedSSHKeyImport.request(for: data) {
            encryptedImport = request
        } else {
            try viewModel.importManagedSSHKey(data)
        }
    }

    private func reload() {
        do {
            // Finish vault work before animating the published list changes.
            let refreshed = try viewModel.managedSSHKeys()
            publishChange { keys = refreshed; errorMessage = nil }
            loaded = true
        } catch {
            // Keep the last readable list visible while Retry is offered.
            show(error)
        }
    }

    private func show(_ error: Error) {
        let message = (error as? SSHPrivateKey.Failure)?.errorDescription
            ?? (error as? DeviceListViewModel.KeyManagementFailure)?.errorDescription
            ?? AppLocalization.string("Could not read the saved SSH key from Keychain.")
        publishChange { errorMessage = message }
    }

    private func publishChange(_ update: () -> Void) {
        if loaded && !reduceMotion {
            withAnimation(.easeOut(duration: 0.18), update)
        } else {
            update()
        }
    }
}
