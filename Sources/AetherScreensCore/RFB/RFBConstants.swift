import Foundation

/// Constants and enumerations for the RFB (Remote Framebuffer) protocol (RFC 6143).
public enum RFBConstants {
    /// Supported RFB protocol version string (12 bytes including newline).
    public static let protocolVersion38 = "RFB 003.008\n"
    public static let protocolVersion37 = "RFB 003.007\n"
    public static let protocolVersion33 = "RFB 003.003\n"
    
    /// Default standard VNC port.
    public static let defaultPort: UInt16 = 5900

    /// Client-to-server message types.
    public enum ClientMessageType: UInt8 {
        case setPixelFormat = 0
        case setEncodings = 2
        case framebufferUpdateRequest = 3
        case keyEvent = 4
        case pointerEvent = 5
        case clientCutText = 6
    }

    /// Server-to-client message types.
    public enum ServerMessageType: UInt8 {
        case framebufferUpdate = 0
        case setColourMapEntries = 1
        case bell = 2
        case serverCutText = 3
    }

    /// RFB Security / Authentication types.
    public struct SecurityType: RawRepresentable, Equatable, Hashable, CustomStringConvertible, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        public static let invalid = SecurityType(rawValue: 0)
        public static let none = SecurityType(rawValue: 1)
        public static let vncAuth = SecurityType(rawValue: 2)
        public static let tight = SecurityType(rawValue: 16)
        public static let veNCrypt = SecurityType(rawValue: 19)
        public static let ardDiffieHellman = SecurityType(rawValue: 30)
        public static let ardAuth33 = SecurityType(rawValue: 33)
        public static let ardAuth35 = SecurityType(rawValue: 35)
        public static let ardAuth36 = SecurityType(rawValue: 36)

        public var description: String {
            switch self {
            case .invalid: return "Invalid (0)"
            case .none: return "None (1)"
            case .vncAuth: return "VNC Auth (2)"
            case .tight: return "Tight (16)"
            case .veNCrypt: return "VeNCrypt (19)"
            case .ardDiffieHellman: return "Apple ARD DH (30)"
            case .ardAuth33: return "Apple ARD (33)"
            case .ardAuth35: return "Apple ARD (35)"
            case .ardAuth36: return "Apple ARD (36)"
            default: return "Unknown (\(rawValue))"
            }
        }
    }

    /// Encodings supported by RFB.
    public struct EncodingType: RawRepresentable, Equatable, Hashable, Sendable {
        public let rawValue: Int32
        public init(rawValue: Int32) { self.rawValue = rawValue }

        public static let raw = EncodingType(rawValue: 0)
        public static let copyRect = EncodingType(rawValue: 1)
        public static let rre = EncodingType(rawValue: 2)
        public static let corre = EncodingType(rawValue: 4)
        public static let hextile = EncodingType(rawValue: 5)
        public static let zlib = EncodingType(rawValue: 6)
        public static let tight = EncodingType(rawValue: 7)
        public static let zrle = EncodingType(rawValue: 16)

        // Pseudo-encodings
        public static let cursor = EncodingType(rawValue: -239)
        public static let desktopSize = EncodingType(rawValue: -223)
        public static let lastRect = EncodingType(rawValue: -224)
    }

    /// Mouse button mask flags for PointerEvent.
    public struct ButtonMask: OptionSet, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        public static let left       = ButtonMask(rawValue: 1 << 0)
        public static let middle     = ButtonMask(rawValue: 1 << 1)
        public static let right      = ButtonMask(rawValue: 1 << 2)
        public static let scrollUp   = ButtonMask(rawValue: 1 << 3)
        public static let scrollDown  = ButtonMask(rawValue: 1 << 4)
        public static let scrollLeft  = ButtonMask(rawValue: 1 << 5)
        public static let scrollRight = ButtonMask(rawValue: 1 << 6)
    }
}
