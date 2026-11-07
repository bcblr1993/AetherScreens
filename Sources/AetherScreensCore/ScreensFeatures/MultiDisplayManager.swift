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
    public enum VirtualSplitMode: String, CaseIterable, Identifiable, Sendable {
        case none = "Server Layout"
        case twoHorizontal = "Split 2× Side-by-Side"
        case threeHorizontal = "Split 3× Side-by-Side"
        case twoVertical = "Split 2× Top & Bottom"

        public var id: String { rawValue }
    }

    @Published public private(set) var availableDisplays: [DisplayInfo]
    @Published public private(set) var selectedDisplayId: Int = 0 // 0 = full framebuffer
    @Published public private(set) var virtualSplitMode: VirtualSplitMode = .none
    private let lock = NSLock()
    private var snapshot: [DisplayInfo]
    private var selection = 0
    private var layoutSize: CGSize?
    private var lastFramebufferSize = CGSize(width: 2560, height: 1600)
    public var onDisplaySelected: (@Sendable (DisplayInfo?) -> Void)?

    public init() {
        let initial = [Self.fullDisplay(width: 2560, height: 1600)]
        availableDisplays = initial
        snapshot = initial
    }

    private static func fullDisplay(width: Int, height: Int) -> DisplayInfo {
        DisplayInfo(id: 0, name: "All Displays", bounds: CGRect(x: 0, y: 0, width: width, height: height))
    }

    private static func virtualDisplays(width: Int, height: Int, mode: VirtualSplitMode) -> [DisplayInfo] {
        var result = [fullDisplay(width: width, height: height)]
        guard width > 0, height > 0 else { return result }
        switch mode {
        case .none:
            break
        case .twoHorizontal:
            let half = width / 2
            guard half > 0 else { break }
            result.append(DisplayInfo(id: 1, name: "Display 1", bounds: CGRect(x: 0, y: 0, width: half, height: height)))
            result.append(DisplayInfo(id: 2, name: "Display 2", bounds: CGRect(x: half, y: 0, width: width - half, height: height)))
        case .threeHorizontal:
            let third = width / 3
            guard third > 0 else { break }
            result.append(DisplayInfo(id: 1, name: "Display 1", bounds: CGRect(x: 0, y: 0, width: third, height: height)))
            result.append(DisplayInfo(id: 2, name: "Display 2", bounds: CGRect(x: third, y: 0, width: third, height: height)))
            result.append(DisplayInfo(id: 3, name: "Display 3", bounds: CGRect(x: third * 2, y: 0, width: width - third * 2, height: height)))
        case .twoVertical:
            let halfH = height / 2
            guard halfH > 0 else { break }
            result.append(DisplayInfo(id: 1, name: "Display 1", bounds: CGRect(x: 0, y: 0, width: width, height: halfH)))
            result.append(DisplayInfo(id: 2, name: "Display 2", bounds: CGRect(x: 0, y: halfH, width: width, height: height - halfH)))
        }
        return result
    }

    /// Framebuffer aspect ratio alone cannot identify physical monitors.
    public func updateFromFramebuffer(width: Int, height: Int) {
        lastFramebufferSize = CGSize(width: width, height: height)
        guard layoutSize != CGSize(width: width, height: height) else { return }
        if virtualSplitMode != .none {
            replaceDisplays(Self.virtualDisplays(width: width, height: height, mode: virtualSplitMode))
        } else {
            reset(width: width, height: height)
        }
    }

    /// Reset server layout when reconnecting or receiving a legacy DesktopSize update.
    public func reset(width: Int, height: Int) {
        layoutSize = nil
        lastFramebufferSize = CGSize(width: width, height: height)
        virtualSplitMode = .none
        replaceDisplays([Self.fullDisplay(width: width, height: height)], forceSelection: 0)
    }

    public func setVirtualSplitMode(_ mode: VirtualSplitMode) {
        guard virtualSplitMode != mode else { return }
        virtualSplitMode = mode
        let w = Int(lastFramebufferSize.width)
        let h = Int(lastFramebufferSize.height)
        if mode == .none {
            replaceDisplays([Self.fullDisplay(width: w, height: h)], forceSelection: 0)
        } else {
            layoutSize = nil
            replaceDisplays(Self.virtualDisplays(width: w, height: h, mode: mode))
        }
    }

    public func cycleNextDisplay() {
        lock.lock()
        let displays = snapshot
        let currentIdx = displays.firstIndex(where: { $0.id == selection }) ?? 0
        let nextIdx = displays.isEmpty ? 0 : (currentIdx + 1) % displays.count
        let nextID = displays.isEmpty ? 0 : displays[nextIdx].id
        lock.unlock()
        selectDisplay(id: nextID)
    }

    public func updateFromLayout(_ layout: RFBDisplayLayout) {
        layoutSize = CGSize(width: Int(layout.width), height: Int(layout.height))
        lastFramebufferSize = CGSize(width: Int(layout.width), height: Int(layout.height))
        virtualSplitMode = .none
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
