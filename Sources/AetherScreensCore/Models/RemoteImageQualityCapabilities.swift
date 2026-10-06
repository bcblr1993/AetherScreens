import Foundation

/// Negotiated image capabilities of the active transport. Desktop scaling and
/// progressive refinement are independent features: a smaller lossless frame
/// does not demonstrate that the server sent progressively finer image passes.
public struct RemoteImageQualityCapabilities: Equatable, Sendable {
    public enum ProgressiveAdaptiveQuality: Equatable, Sendable {
        case notConnected
        /// The client has no verified decoder for Apple's progressive codec.
        /// This says nothing about whether the remote Mac can encode it.
        case clientDecoderUnavailable
    }

    public let progressiveAdaptiveQuality: ProgressiveAdaptiveQuality
    /// True only after an Apple layout supplies the server's scaling geometry.
    public let supportsServerScaling: Bool
}
