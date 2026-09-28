import Foundation
import CoreGraphics

/// Model representing a physical or virtual display on the remote Mac.
public struct DisplayInfo: Identifiable, Equatable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let bounds: CGRect
    public let isMain: Bool

    public init(id: Int, name: String, bounds: CGRect, isMain: Bool = false) {
        self.id = id
        self.name = name
        self.bounds = bounds
        self.isMain = isMain
    }

    public var resolutionDescription: String {
        "\(Int(bounds.width)) × \(Int(bounds.height))"
    }
}

/// Manages multi-monitor display switching for remote Macs with multiple monitors.
public final class MultiDisplayManager: ObservableObject, @unchecked Sendable {
    @Published public private(set) var availableDisplays: [DisplayInfo] = []
    @Published public private(set) var selectedDisplayId: Int = 0 // 0 = All Displays

    private let lock = NSLock()
    public var onDisplaySelected: (@Sendable (DisplayInfo?) -> Void)?

    public init() {
        // Default to single display representation until remote resolution is known
        self.availableDisplays = [
            DisplayInfo(id: 0, name: "All Displays", bounds: CGRect(x: 0, y: 0, width: 2560, height: 1600), isMain: true)
        ]
    }

    /// Configure available displays based on remote framebuffer dimensions
    public func updateFromFramebuffer(width: Int, height: Int) {
        lock.lock()
        defer { lock.unlock() }

        // Multi-monitor aspect ratio detection
        if width >= height * 2 {
            // Dual side-by-side displays
            let halfWidth = CGFloat(width) / 2.0
            let h = CGFloat(height)
            self.availableDisplays = [
                DisplayInfo(id: 0, name: "All Displays", bounds: CGRect(x: 0, y: 0, width: CGFloat(width), height: h), isMain: true),
                DisplayInfo(id: 1, name: "Display 1 (Left)", bounds: CGRect(x: 0, y: 0, width: halfWidth, height: h), isMain: true),
                DisplayInfo(id: 2, name: "Display 2 (Right)", bounds: CGRect(x: halfWidth, y: 0, width: halfWidth, height: h), isMain: false)
            ]
        } else {
            self.availableDisplays = [
                DisplayInfo(id: 0, name: "Main Display", bounds: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)), isMain: true)
            ]
        }
    }

    /// Switch active display view
    public func selectDisplay(id: Int) {
        lock.lock()
        selectedDisplayId = id
        let display = availableDisplays.first { $0.id == id }
        lock.unlock()

        onDisplaySelected?(display)
    }

    /// Get currently active display
    public var currentDisplay: DisplayInfo? {
        lock.lock()
        defer { lock.unlock() }
        return availableDisplays.first { $0.id == selectedDisplayId }
    }

    /// Translates a local point within the currently selected display into global framebuffer coordinates
    public func translateCoordinates(x: CGFloat, y: CGFloat, remoteTotalWidth: CGFloat, remoteTotalHeight: CGFloat) -> (UInt16, UInt16) {
        lock.lock()
        let active = availableDisplays.first { $0.id == selectedDisplayId }
        lock.unlock()

        guard let disp = active, disp.id > 0 else {
            // Full desktop (All Displays)
            let clampedX = UInt16(min(max(0, x), remoteTotalWidth))
            let clampedY = UInt16(min(max(0, y), remoteTotalHeight))
            return (clampedX, clampedY)
        }

        // Offset by selected display origin
        let globalX = disp.bounds.origin.x + x
        let globalY = disp.bounds.origin.y + y
        let clampedX = UInt16(min(max(0, globalX), remoteTotalWidth))
        let clampedY = UInt16(min(max(0, globalY), remoteTotalHeight))
        return (clampedX, clampedY)
    }
}
