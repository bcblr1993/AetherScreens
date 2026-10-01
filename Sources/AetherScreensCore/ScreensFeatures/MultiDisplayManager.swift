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

/// Publishes display choices on the UI thread; pointer translation reads a locked snapshot.
public final class MultiDisplayManager: ObservableObject, @unchecked Sendable {
    @Published public private(set) var availableDisplays: [DisplayInfo]
    @Published public private(set) var selectedDisplayId: Int = 0 // 0 = full framebuffer
    private let lock = NSLock()
    private var snapshot: [DisplayInfo]
    private var selection = 0
    private var layoutSize: CGSize?
    public var onDisplaySelected: (@Sendable (DisplayInfo?) -> Void)?

    public init() {
        let initial = [Self.fullDisplay(width: 2560, height: 1600)]
        availableDisplays = initial
        snapshot = initial
    }

    private static func fullDisplay(width: Int, height: Int) -> DisplayInfo {
        DisplayInfo(id: 0, name: "All Displays", bounds: CGRect(x: 0, y: 0, width: width, height: height))
    }

    /// Framebuffer aspect ratio alone cannot identify physical monitors.
    public func updateFromFramebuffer(width: Int, height: Int) {
        guard layoutSize != CGSize(width: width, height: height) else { return }
        reset(width: width, height: height)
    }

    /// Reset server layout when reconnecting or receiving a legacy DesktopSize update.
    public func reset(width: Int, height: Int) {
        layoutSize = nil
        replaceDisplays([Self.fullDisplay(width: width, height: height)], forceSelection: 0)
    }

    public func updateFromLayout(_ layout: RFBDisplayLayout) {
        layoutSize = CGSize(width: Int(layout.width), height: Int(layout.height))
        var displays = [Self.fullDisplay(width: Int(layout.width), height: Int(layout.height))]
        displays += layout.screens.enumerated().map { index, screen in
            // Wire ID zero is valid; reserve UI ID zero exclusively for the full desktop.
            DisplayInfo(id: Int(screen.id) + 1, name: "Display \(index + 1)",
                        bounds: CGRect(x: Int(screen.x), y: Int(screen.y), width: Int(screen.width), height: Int(screen.height)))
        }
        replaceDisplays(displays)
    }

    private func replaceDisplays(_ displays: [DisplayInfo], forceSelection: Int? = nil) {
        lock.lock()
        let previous = snapshot.first { $0.id == selection }
        let nextID = forceSelection ?? (displays.contains { $0.id == selection } ? selection : 0)
        snapshot = displays
        selection = nextID
        let next = displays.first { $0.id == nextID }
        lock.unlock()
        // Combine subscribers may read currentDisplay synchronously. Never publish under the lock.
        if availableDisplays != displays { availableDisplays = displays }
        if selectedDisplayId != nextID { selectedDisplayId = nextID }
        if previous != next && (previous?.id != 0 || next?.id != 0) { onDisplaySelected?(next) }
    }

    public func selectDisplay(id: Int) {
        lock.lock()
        guard let display = snapshot.first(where: { $0.id == id }), selection != id else { lock.unlock(); return }
        selection = id
        lock.unlock()
        selectedDisplayId = id
        onDisplaySelected?(display)
    }

    public var currentDisplay: DisplayInfo? {
        lock.lock()
        defer { lock.unlock() }
        return snapshot.first { $0.id == selection }
    }

    public func translateCoordinates(x: CGFloat, y: CGFloat, remoteTotalWidth: CGFloat, remoteTotalHeight: CGFloat) -> (UInt16, UInt16) {
        let bounds = currentDisplay?.bounds ?? CGRect(x: 0, y: 0, width: remoteTotalWidth, height: remoteTotalHeight)
        func coordinate(_ value: CGFloat, origin: CGFloat, extent: CGFloat, total: CGFloat) -> UInt16 {
            let local = value.isFinite ? min(max(0, value), max(0, extent - 1)) : 0
            return UInt16(min(CGFloat(UInt16.max), max(0, min(origin + local, max(0, total - 1)))))
        }
        return (coordinate(x, origin: bounds.minX, extent: bounds.width, total: remoteTotalWidth),
                coordinate(y, origin: bounds.minY, extent: bounds.height, total: remoteTotalHeight))
    }
}
