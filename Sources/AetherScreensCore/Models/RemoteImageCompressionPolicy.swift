import Foundation

/// Apple Screen Sharing renders a smaller framebuffer before encoding it.
public enum RemoteImageCompressionPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case always = "Always"
    case remoteOnly = "Only for Remote Connections"
    case never = "Never"

    public var id: Self { self }

    func factor(isLocalConnection: Bool?) -> Double {
        switch self {
        case .always: return 0.5
        case .remoteOnly: return isLocalConnection == false ? 0.5 : 1
        case .never: return 1
        }
    }
}
