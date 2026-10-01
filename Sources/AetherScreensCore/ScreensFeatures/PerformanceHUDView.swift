import SwiftUI

/// Screens-style performance diagnostic badge displaying real-time FPS, Latency, and Throughput.
public struct PerformanceHUDView: View {
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    @ObservedObject public var metrics: PerformanceMetrics
    @State private var isExpanded: Bool = false
    public let isTailscale: Bool

    public init(metrics: PerformanceMetrics = .shared, isTailscale: Bool = false) {
        self.metrics = metrics
        self.isTailscale = isTailscale
    }

    public var body: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                // Optimal Status Light
                Circle()
                    .fill(metrics.latencyMs > 0 ? (metrics.isOptimal ? Color.green : Color.orange) : Color.secondary)
                    .frame(width: 7, height: 7)

                // FPS Counter
                HStack(spacing: 2) {
                    Text("\(Int(metrics.currentFPS))")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                    Text("FPS")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                Divider()
                    .frame(height: 12)

                // TCP RTT excludes remote processing and display latency.
                HStack(spacing: 2) {
                    if isExpanded {
                        Text(AppLocalization.string("TCP RTT"))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    Text(metrics.latencyMs > 0 ? "\(Int(metrics.latencyMs))" : "—")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                    Text("ms")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                if isExpanded {
                    Divider()
                        .frame(height: 12)

                    // Bandwidth
                    HStack(spacing: 2) {
                        Text(bandwidthText)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }

                    Divider()
                        .frame(height: 12)

                    // Tailscale Tag
                    HStack(spacing: 3) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 8))
                        Text(AppLocalization.string(isTailscale ? "Tailscale" : "LAN / Host"))
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .help(AppLocalization.string("Network round-trip time; excludes remote processing and display delay."))
    }

    private var bandwidthText: String {
        if metrics.bandwidthKbps / 8 > 1024 {
            return String(format: "%.1f MB/s", metrics.bandwidthKbps / (8 * 1024.0))
        } else {
            return "\(Int(metrics.bandwidthKbps / 8)) KB/s"
        }
    }
}
