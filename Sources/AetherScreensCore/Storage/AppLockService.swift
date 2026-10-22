import Foundation
import LocalAuthentication
import Combine
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Timeout interval before application automatically locks when placed in background.
public enum AutoLockInterval: Int, CaseIterable, Identifiable, Sendable {
    case immediately = 0
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case never = -1

    public var id: Int { rawValue }

    public var titleKey: String {
        switch self {
        case .immediately: return "Immediately"
        case .oneMinute: return "After 1 minute"
        case .fiveMinutes: return "After 5 minutes"
        case .fifteenMinutes: return "After 15 minutes"
        case .never: return "Never"
        }
    }
}

/// Available biometric authentication mechanism on the current device.
public enum BiometryType: Sendable {
    case none
    case touchID
    case faceID
    case opticID

    public var displayNameKey: String {
        switch self {
        case .none: return "Passcode"
        case .touchID: return "Touch ID"
        case .faceID: return "Face ID"
        case .opticID: return "Optic ID"
        }
    }

    public var systemIconName: String {
        switch self {
        case .none: return "lock.fill"
        case .touchID: return "touchid"
        case .faceID: return "faceid"
        case .opticID: return "opticid"
        }
    }
}

/// Manages application locking state, biometric / passcode authentication, and background timeout protection.
@MainActor
public final class AppLockService: ObservableObject {
    public static let shared = AppLockService(observesApplicationLifecycle: true)

    private enum Keys {
        static let isLockEnabled = "com.aethernative.aetherscreens.applock.enabled"
        static let autoLockInterval = "com.aethernative.aetherscreens.applock.interval"
    }

    @Published public private(set) var isLocked: Bool = false

    /// True while the lock must hide remote desktops and refuse new sessions.
    public var blocksAccess: Bool { isLockEnabled && isLocked }
    @Published public var isLockEnabled: Bool {
        didSet {
            userDefaults.set(isLockEnabled, forKey: Keys.isLockEnabled)
            if !isLockEnabled {
                isLocked = false
            }
        }
    }

    @Published public var autoLockInterval: AutoLockInterval {
        didSet {
            userDefaults.set(autoLockInterval.rawValue, forKey: Keys.autoLockInterval)
        }
    }

    @Published public private(set) var biometryType: BiometryType = .none

    private let userDefaults: UserDefaults
    private var lastBackgroundDate: Date?
    private let authEvaluator: (@Sendable (String) async -> Bool)?
    private let biometryEvaluator: (@Sendable () -> BiometryType)?
    private var pendingUnlock: Task<Bool, Never>?
    private var lifecycleObservers: [NSObjectProtocol] = []

    public init(
        userDefaults: UserDefaults = .standard,
        authEvaluator: (@Sendable (String) async -> Bool)? = nil,
        biometryEvaluator: (@Sendable () -> BiometryType)? = nil,
        observesApplicationLifecycle: Bool = false
    ) {
        self.userDefaults = userDefaults
        self.authEvaluator = authEvaluator
        self.biometryEvaluator = biometryEvaluator

        self.isLockEnabled = userDefaults.bool(forKey: Keys.isLockEnabled)
        if let storedInterval = userDefaults.object(forKey: Keys.autoLockInterval) as? Int,
           let interval = AutoLockInterval(rawValue: storedInterval) {
            self.autoLockInterval = interval
        } else {
            self.autoLockInterval = .immediately
        }

        refreshBiometryType()

        // If enabled on app start, start in locked state
        if isLockEnabled {
            self.isLocked = true
        }
        if observesApplicationLifecycle { observeApplicationLifecycle() }
    }

    /// Session windows outlive the library window, and on macOS switching apps never reports a
    /// background scene phase, so lock timing follows the application rather than one scene.
    private func observeApplicationLifecycle() {
        let center = NotificationCenter.default
        #if canImport(AppKit)
        let background = NSApplication.didResignActiveNotification
        let foreground = NSApplication.didBecomeActiveNotification
        #elseif canImport(UIKit)
        let background = UIApplication.didEnterBackgroundNotification
        let foreground = UIApplication.willEnterForegroundNotification
        #endif
        lifecycleObservers = [
            center.addObserver(forName: background, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleAppDidEnterBackground() }
            },
            center.addObserver(forName: foreground, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleAppWillEnterForeground() }
            }
        ]
    }

    public func refreshBiometryType() {
        if let biometryEvaluator {
            self.biometryType = biometryEvaluator()
            return
        }

        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch context.biometryType {
            case .faceID:
                self.biometryType = .faceID
            case .touchID:
                self.biometryType = .touchID
            case .opticID:
                self.biometryType = .opticID
            default:
                self.biometryType = .none
            }
        } else {
            self.biometryType = .none
        }
    }

    /// Explicitly trigger app lock if locking is enabled.
    public func lock() {
        guard isLockEnabled else { return }
        isLocked = true
    }

    /// Record time when app moves to background.
    public func handleAppDidEnterBackground(date: Date = Date()) {
        guard isLockEnabled else { return }
        lastBackgroundDate = date
    }

    /// Check elapsed time and lock if timeout interval exceeded.
    public func handleAppWillEnterForeground(date: Date = Date()) {
        guard isLockEnabled, !isLocked else { return }
        guard let lastBackgroundDate else {
            // No previous background timestamp, lock if set to immediately
            if autoLockInterval == .immediately {
                isLocked = true
            }
            return
        }

        if autoLockInterval == .immediately {
            isLocked = true
        } else if autoLockInterval != .never {
            let elapsed = date.timeIntervalSince(lastBackgroundDate)
            if elapsed >= Double(autoLockInterval.rawValue) {
                isLocked = true
            }
        }
    }

    /// Prompt user for biometric / passcode authentication to unlock.
    /// Every locked window offers its own prompt; concurrent requests share one authentication.
    @discardableResult
    public func unlock(reason: String = AppLocalization.string("Unlock AetherScreens to access your remote computers")) async -> Bool {
        if let pendingUnlock { return await pendingUnlock.value }
        let task = Task { @MainActor in await self.performUnlock(reason: reason) }
        pendingUnlock = task
        let result = await task.value
        pendingUnlock = nil
        return result
    }

    private func performUnlock(reason: String) async -> Bool {
        guard isLockEnabled else {
            isLocked = false
            return true
        }

        if let authEvaluator {
            let success = await authEvaluator(reason)
            if success {
                isLocked = false
            }
            return success
        }

        let context = LAContext()
        context.localizedCancelTitle = AppLocalization.string("Cancel")

        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if success {
                isLocked = false
                lastBackgroundDate = nil
                return true
            }
        } catch {
            // Authentication failed or was cancelled by user
        }

        return false
    }
}
