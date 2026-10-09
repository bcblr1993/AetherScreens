import SwiftUI

/// A compact desktop preview with a clear connection state and one primary action.
public struct DeviceCardView: View {
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var thumbnail: CGImage?
    @State private var thumbnailRevision: UInt64 = 0
    @State private var isVisible = false
    private struct ThumbnailRequest: Hashable {
        let deviceID: UUID
        let revision: UInt64
        let lastConnected: Date?
    }
    public let device: RemoteDevice
    public let onConnect: () -> Void
    public var onWake: (() -> Void)? = nil

    public init(device: RemoteDevice, onConnect: @escaping () -> Void, onWake: (() -> Void)? = nil) {
        self.device = device
        self.onConnect = onConnect
        self.onWake = onWake
        _thumbnail = State(initialValue: ThumbnailStore.shared.cachedThumbnail(for: device.id))
    }

    public var body: some View {
        Button(action: onConnect) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color(red: 0.14, green: 0.18, blue: 0.23))

                    if let thumbnail {
                        Image(decorative: thumbnail, scale: 1.0)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 154)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .transition(.opacity)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: device.deviceType.systemIcon)
                                .font(.system(size: 38, weight: .ultraLight))
                                .foregroundStyle(.white.opacity(0.84))
                            Text(AppLocalization.string(device.deviceType.rawValue).uppercased())
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .tracking(2)
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    VStack {
                        HStack {
                            Spacer()
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(device.isTailscaleNode && device.isOnline ? Color(red: 0.30, green: 0.77, blue: 0.53) : .gray)
                                    .frame(width: 6, height: 6)
                                Text(AppLocalization.string(device.isTailscaleNode ? (device.isOnline ? "Tailnet Online" : "Tailnet Offline") : "Saved"))
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.6), in: Capsule())
                        }
                        Spacer()
                    }
                    .padding(10)
                }
                .frame(height: 154)

                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(device.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            Text(device.host)
                            Text(":" + String(device.port))
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(device.isOnline ? Color.accentColor : Color.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color.accentColor.opacity(0.09), in: Circle())
                }
                .padding(.horizontal, 4)
                .padding(.top, 13)
                .padding(.bottom, 5)
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.055), radius: 14, y: 5)
        }
        .buttonStyle(ControlPressStyle(pressedScale: 0.985))
        .accessibilityLabel(AppLocalization.format("Connect to %@", device.name))
        .accessibilityValue(AppLocalization.string(thumbnail == nil ? "No desktop preview" : "Desktop preview available"))
        .onAppear {
            isVisible = true
            if let cached = ThumbnailStore.shared.cachedThumbnail(for: device.id) { thumbnail = cached }
            thumbnailRevision &+= 1
        }
        .onDisappear {
            isVisible = false
            thumbnail = nil
        }
        .task(id: ThumbnailRequest(deviceID: device.id, revision: thumbnailRevision, lastConnected: device.lastConnected)) {
            let loaded = await ThumbnailStore.shared.loadThumbnail(for: device.id)
            guard !Task.isCancelled, isVisible else { return }
            let current = ThumbnailStore.shared.cachedThumbnail(for: device.id) ?? loaded
            updateThumbnail(current)
        }
        .onReceive(ThumbnailStore.shared.updates.receive(on: DispatchQueue.main)) { id in
            guard isVisible, id == device.id else { return }
            if let cached = ThumbnailStore.shared.cachedThumbnail(for: id) {
                updateThumbnail(cached)
            } else {
                thumbnailRevision &+= 1
            }
        }
    }
    private func updateThumbnail(_ current: CGImage?) {
        guard thumbnail !== current else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            thumbnail = current
        }
    }

}
