import SwiftUI

/// Screens-style performance diagnostic badge displaying real-time FPS, Latency, and Throughput.
public struct PerformanceHUDView: View {
    @ObservedObject public var metrics: PerformanceMetrics
    @State private var isExpanded: Bool = false

    public init(metrics: PerformanceMetrics = .shared) {
        self.metrics = metrics
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
                    .fill(metrics.isOptimal ? Color.green : Color.orange)
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

                // Latency Counter
                HStack(spacing: 2) {
                    Text("\(Int(metrics.latencyMs))")
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
                        Text("Tailscale")
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
    }

    private var bandwidthText: String {
        if metrics.bandwidthKbps > 1024 {
            return String(format: "%.1f MB/s", metrics.bandwidthKbps / 1024.0)
        } else {
            return "\(Int(metrics.bandwidthKbps)) KB/s"
        }
    }
}
