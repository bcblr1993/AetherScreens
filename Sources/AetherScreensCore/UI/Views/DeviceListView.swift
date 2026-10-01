import SwiftUI

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
    @StateObject private var viewModel = DeviceListViewModel()
    @State private var selectedCategory: DeviceCategory = .all
    @State private var showingAddSheet = false
    @State private var showingQuickConnectSheet = false
    @State private var pendingQuickSession: SessionViewModel?
    @State private var showingSettingsSheet = false
    @State private var activeSessionVM: SessionViewModel?
    @State private var editingDevice: RemoteDevice?
    @State private var showingLogs = false

    private let columns = [
        GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 16)
    ]

    public init() {}

    public var body: some View {
        #if os(macOS)
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
        } detail: {
            mainGridView
                .navigationTitle(selectedCategory.rawValue)
        }
        .sheet(item: $activeSessionVM, onDismiss: { viewModel.reload() }) { sessionVM in
            RemoteDesktopView(viewModel: sessionVM)
                .frame(minWidth: 800, minHeight: 560)
        }
        .sheet(item: $editingDevice) { dev in
            EditDeviceSheet(device: dev, viewModel: viewModel)
        }
        .sheet(isPresented: $showingLogs) {
            DiagnosticLogView()
        }
        .sheet(isPresented: $showingAddSheet) {
            AddDeviceSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showingQuickConnectSheet, onDismiss: openPendingQuickSession) {
            quickConnectSheet
        }
        .sheet(isPresented: $showingSettingsSheet) {
            TailscaleSettingsSheet(viewModel: viewModel)
        }
        #else
        NavigationStack {
            mainGridView
                .navigationTitle("AetherScreens")
                .navigationBarTitleDisplayMode(.inline)
                .fullScreenCover(item: $activeSessionVM, onDismiss: { viewModel.reload() }) { sessionVM in
                    RemoteDesktopView(viewModel: sessionVM)
                }
                .sheet(item: $editingDevice) { dev in
                    EditDeviceSheet(device: dev, viewModel: viewModel)
                }
                .sheet(isPresented: $showingLogs) {
                    DiagnosticLogView()
                }
                .sheet(isPresented: $showingAddSheet) {
                    AddDeviceSheet(viewModel: viewModel)
                }
                .sheet(isPresented: $showingQuickConnectSheet, onDismiss: openPendingQuickSession) {
                    quickConnectSheet
                }
                .sheet(isPresented: $showingSettingsSheet) {
                    TailscaleSettingsSheet(viewModel: viewModel)
                }
        }
        #endif
    }

    // MARK: - Sidebar (macOS)

    #if os(macOS)
    private var sidebarContent: some View {
        List(DeviceCategory.allCases, selection: $selectedCategory) { category in
            HStack {
                Label(category.rawValue, systemImage: category.icon)
                Spacer()
                if category == .nearby && !viewModel.discoveredNearbyMacs.isEmpty {
                    Text("\(viewModel.discoveredNearbyMacs.count)")
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
                        Text(err)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Spacer()
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
                        Text(notice)
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                        Spacer()
                        Button {
                            viewModel.statusNotice = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(Color.green.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                }

                // Discovered Nearby Macs (Bonjour) Section
                if !viewModel.discoveredNearbyMacs.isEmpty && (selectedCategory == .all || selectedCategory == .nearby) {
                    nearbyBonjourSection
                }

                // Configured Saved Computers Grid
                let devices = displayedDevices
                if devices.isEmpty && !showsNearbyDevices {
                    emptyStateView
                } else if !devices.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        if !viewModel.discoveredNearbyMacs.isEmpty {
                            Text("Your computers")
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
                                .contextMenu {
                                    Button {
                                        openSession(for: device)
                                    } label: {
                                        Label("Connect", systemImage: "arrow.up.right.video")
                                    }

                                    Button {
                                        editingDevice = device
                                    } label: {
                                        Label("Edit Computer...", systemImage: "pencil")
                                    }

                                    if let mac = device.macAddress, !mac.isEmpty {
                                        Button {
                                            viewModel.wakeDevice(device)
                                        } label: {
                                            Label("Wake Mac (WOL)", systemImage: "bolt.fill")
                                        }
                                    }

                                    Divider()

                                    Button(role: .destructive) {
                                        viewModel.deleteDevice(device)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            .padding(.vertical, 24)
        }
        .background(dashboardBackground)
        .searchable(text: $viewModel.searchText, prompt: "Search computers or Tailscale IP")
        .refreshable {
            await viewModel.syncTailscale()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Diagnostic Logs Button
                Button {
                    showingLogs = true
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                }
                .help("View Diagnostic Logs")
                .accessibilityLabel("Diagnostic Logs")

                // Sync Tailscale Button
                Button {
                    Task {
                        await viewModel.syncTailscale()
                    }
                } label: {
                    if viewModel.isSyncingTailscale {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .help("Sync Tailscale Online Nodes")
                .accessibilityLabel("Sync Tailscale Devices")

                // Temporary or optionally saved connection
                Button {
                    showingQuickConnectSheet = true
                } label: {
                    Image(systemName: "bolt.horizontal.circle")
                }
                .help("Quick Connect")
                .accessibilityLabel("Quick Connect")

                // Add Computer Button
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add Computer Manually")
                .accessibilityLabel("Add Computer")
            }

            #if canImport(UIKit)
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingSettingsSheet = true
                } label: {
                    Image(systemName: "gear")
                }
                .accessibilityLabel("Settings")
            }
            #endif
        }
    }

    // MARK: - Nearby Bonjour Macs Section

    private var dashboardHeader: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("WORKSPACE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.secondary)
                Text("Your screens")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .tracking(-0.7)
                Text("Connect to your computers from anywhere.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text("\(viewModel.filteredDevices.count) computers")
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
                Text("Nearby Macs (Local Wi-Fi)")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Text("\(viewModel.discoveredNearbyMacs.count) discovered")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.discoveredNearbyMacs) { discovered in
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
                        .accessibilityLabel("Add \(discovered.name)")
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
        !viewModel.discoveredNearbyMacs.isEmpty && (selectedCategory == .all || selectedCategory == .nearby)
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
        self.activeSessionVM = session
    }

    private var quickConnectSheet: some View {
        AddDeviceSheet(viewModel: viewModel) { request, saveComputer in
            pendingQuickSession = viewModel.prepareQuickSession(request, saveComputer: saveComputer)
        }
    }

    private func openPendingQuickSession() {
        guard let session = pendingQuickSession else { return }
        pendingQuickSession = nil
        activeSessionVM = session
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "display.2")
                .font(.system(size: 38, weight: .ultraLight))
                .foregroundStyle(.secondary)
                .frame(width: 88, height: 88)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))

            Text(viewModel.searchText.isEmpty ? "No computers here yet" : "No matching computers")
                .font(.system(size: 20, weight: .semibold))

            Text(viewModel.searchText.isEmpty ? "Add a computer to start a remote session. You can also sync devices from your tailnet." : "Try a different name or address.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if viewModel.searchText.isEmpty && selectedCategory == .all {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add computer", systemImage: "plus")
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
    @ObservedObject public var viewModel: DeviceListViewModel
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            Form {
                Section(
                    header: Text("Tailscale API Credentials"),
                    footer: Text("Generate an API Access Token or OAuth Client in your Tailscale Admin Console (Settings > Keys). This allows AetherScreens to automatically discover your online devices.")
                ) {
                    SecureField("API Access Token (tskey-api-...)", text: $viewModel.tailscaleApiKey)
                    TextField("Tailnet Name (Optional, e.g. example.com)", text: $viewModel.tailnetName)
                }

                Section(header: Text("About macOS Screen Sharing")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Open System Settings on Mac > General > Sharing.")
                            .font(.system(size: 13))
                        Text("2. Turn on Screen Sharing.")
                            .font(.system(size: 13))
                        Text("3. Click ℹ️ > Computer Settings > Enable 'VNC viewers may control screen with password'.")
                            .font(.system(size: 13))
                        Text("4. Ensure Tailscale is running on both client and host.")
                            .font(.system(size: 13))
                    }
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Tailscale Settings")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
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
