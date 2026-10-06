import Foundation

public enum PencilGesture: Sendable { case doubleTap, squeeze }

public enum PencilGestureAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case none = "None"
    case toggleToolbar = "Toggle Toolbar Visibility"
    case secondaryClick = "Secondary Click"
    case middleClick = "Middle Click"
    public var id: String { rawValue }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .none
    }
}
