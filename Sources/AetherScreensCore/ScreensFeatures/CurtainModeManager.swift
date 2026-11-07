import Foundation

/// Tracks the local Lock Screen / Curtain Mode privacy state and optional custom message.
public final class CurtainModeManager: ObservableObject, @unchecked Sendable {
    @Published public private(set) var isCurtainActive: Bool = false
    @Published public var customMessage: String?
    private let lock = NSLock()

    public var onCurtainStateChanged: (@Sendable (Bool) -> Void)?

    public init() {}

    /// Effective title displayed on the Curtain / Lock Screen banner.
    public var effectiveNoticeTitle: String {
        if let msg = customMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !msg.isEmpty {
            return msg
        }
        return AppLocalization.string("Lock Screen shortcut sent")
    }

    /// Automatically activates Curtain Mode if the device is configured with `curtainOnConnect == true`.
    @discardableResult
    public func activateForDeviceConnectIfConfigured(_ device: RemoteDevice) -> Bool {
        let trimmedMsg = device.curtainMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        customMessage = (trimmedMsg?.isEmpty == false) ? trimmedMsg : nil
        lock.unlock()
        guard device.curtainOnConnect == true else { return false }
        setCurtain(active: true)
        return true
    }

    /// Toggle the local shortcut notice.
    public func toggleCurtain() {
        lock.lock()
        isCurtainActive.toggle()
        let active = isCurtainActive
        lock.unlock()

        onCurtainStateChanged?(active)
    }

    /// Set curtain state explicitly
    public func setCurtain(active: Bool) {
        lock.lock()
        isCurtainActive = active
        lock.unlock()

        onCurtainStateChanged?(active)
    }
}
