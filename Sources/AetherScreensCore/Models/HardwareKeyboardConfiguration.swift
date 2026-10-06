import Foundation

public struct HardwareKeyboardConfiguration: Codable, Equatable, Sendable {
    public var swapCommandControl: Bool?
    public var commandBackslashSwitchesApps: Bool?
    public var repeatEnabled = true
    public var repeatDelay: Double = 0.5
    public var repeatInterval: Double = 0.05
    public init() {}

    public var validatedDelay: Double {
        repeatDelay.isFinite ? min(2, max(0.2, repeatDelay)) : 0.5
    }
    public var validatedInterval: Double {
        repeatInterval.isFinite ? min(0.5, max(0.03, repeatInterval)) : 0.05
    }
}
