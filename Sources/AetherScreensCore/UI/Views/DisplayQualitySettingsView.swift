import SwiftUI

struct DisplayQualitySettingsView: View {
    @ObservedObject var viewModel: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        headerView

                        if viewModel.isRDP {
                            rdpDisplaySettingsSection
                        } else {
                            vncDisplaySettingsSection
                        }
                    }
                    .padding(20)
                }

                Divider()

                HStack {
                    Spacer()
                    Button(AppLocalization.string("Done")) {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(.regularMaterial)
            }
            .frame(minWidth: 440, idealWidth: 460, maxWidth: 500)
            .navigationTitle(AppLocalization.string("Display Quality"))
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    private var headerView: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: viewModel.isRDP ? "display.2" : "photo.stack")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(AppLocalization.string("Display Quality & Resolution"))
                    .font(.headline)
                Text(viewModel.isRDP
                     ? AppLocalization.string("Windows Remote Desktop (RDP · 32-bit True Color)")
                     : AppLocalization.string("Apple Screen Sharing / VNC Session"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var rdpDisplaySettingsSection: some View {
        VStack(spacing: 14) {
            // Resolution and Color status card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(AppLocalization.string("Current Resolution"), systemImage: "aspectratio")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    let width = Int(viewModel.remoteDesktopSize.width > 0 ? viewModel.remoteDesktopSize.width : CGFloat(viewModel.rdpClient?.framebuffer.width ?? 0))
                    let height = Int(viewModel.remoteDesktopSize.height > 0 ? viewModel.remoteDesktopSize.height : CGFloat(viewModel.rdpClient?.framebuffer.height ?? 0))
                    Text("\(width) × \(height)")
                        .font(.subheadline.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack {
                    Label(AppLocalization.string("Color Depth"), systemImage: "paintpalette")
                        .font(.subheadline)
                    Spacer()
                    Text(AppLocalization.string("32-bit True Color (Hardware Accelerated)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

            // Scaling & Zoom card
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(AppLocalization.string("Scaling & Zoom"), systemImage: "arrow.up.left.and.down.right.magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(Int(round(viewModel.zoomScale * 100)))%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }

                HStack(spacing: 10) {
                    Button {
                        viewModel.zoomScale = 1.0
                        viewModel.viewOffset = .zero
                        viewModel.isPanningViewport = false
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                            Text(AppLocalization.string("Fit to Window"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(viewModel.zoomScale == 1.0 ? .accentColor : .secondary)

                    Button {
                        viewModel.zoomScale = viewModel.actualSizeZoomScale
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "1.magnifyingglass")
                            Text(AppLocalization.string("Actual Size (1:1)"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(abs(viewModel.zoomScale - viewModel.actualSizeZoomScale) < 0.01 ? .accentColor : .secondary)
                }

                Text(AppLocalization.string("Fit to Window scales the remote desktop to fill your screen. Actual Size renders 1:1 pixel for pixel."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var vncDisplaySettingsSection: some View {
        VStack(spacing: 14) {
            // Automatic compression
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { viewModel.automaticDisplayQuality && !viewModel.client.isNativeDisplaySession },
                    set: { viewModel.selectAutomaticDisplayQuality($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppLocalization.string("Automatic Compression"))
                            .font(.subheadline.weight(.medium))
                        Text(AppLocalization.string("Adjusts compression automatically based on network speed."))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("automatic-display-quality")
                .disabled(!viewModel.isForegroundSession || viewModel.client.isNativeDisplaySession)
            }
            .padding(14)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

            // Colors
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(AppLocalization.string("Colors"))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Picker("", selection: Binding(
                        get: { viewModel.displayColorDepth },
                        set: { viewModel.selectDisplayColorDepth($0) }
                    )) {
                        Text(AppLocalization.string("Full Color (32-bit)")).tag(RFBColorDepth.fullColor)
                        Text(AppLocalization.string("Reduced Colors (16-bit)")).tag(RFBColorDepth.rgb565)
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("display-color-depth")
                    .disabled(!viewModel.isForegroundSession)
                }

                Text(AppLocalization.string("Reduced colors use less network data but may show subtle color banding. Changing this setting will reconnect."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
