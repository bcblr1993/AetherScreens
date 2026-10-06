import Foundation
import Security
@testable import AetherScreensCore
@testable import AetherScreensSSH

/// Real session/transport logic with an isolated clipboard by default. A test
/// opting into synchronization supplies its own reader, count and writer.
@MainActor
enum TestSession {
    static func make(
        device: RemoteDevice,
        password: String?,
        isTemporary: Bool = false,
        deviceStore: DeviceStore? = nil,
        keyboardStore: KeyboardToolbarStore? = nil,
        clipboardWriter: (@MainActor @Sendable (String) -> Void)? = nil,
        clipboardFlavorsWriter: (@MainActor @Sendable ([RFBClipboardFlavor]) -> Void)? = nil,
        clipboardReader: (@MainActor @Sendable () -> [RFBClipboardFlavor])? = nil,
        clipboardAsyncReader: (@MainActor @Sendable () async -> [RFBClipboardFlavor]?)? = nil,
        clipboardCountReader: (@MainActor @Sendable () -> Int)? = nil,
        userPasswordReader: (@MainActor @Sendable (RemoteDevice) -> String?)? = nil,
        userPasswordAuthentication: (@MainActor @Sendable () async -> Bool)? = nil,
        sshCredentials: SSHSessionCredentials? = nil,
        sshKeychain: SSHKeychainStore? = nil,
        thumbnailStore: ThumbnailStore? = nil,
        curtainRecoveryStore: CurtainRecoveryStore? = nil
    ) -> SessionViewModel {
        let devices = deviceStore ?? TestStorage.make()
        return SessionViewModel(
            device: device, password: password, isTemporary: isTemporary,
            deviceStore: devices,
            keyboardStore: keyboardStore ?? KeyboardToolbarStore(defaults: devices.synchronizationDefaults),
            clipboardWriter: clipboardWriter ?? { _ in },
            clipboardFlavorsWriter: clipboardFlavorsWriter,
            clipboardReader: clipboardReader ?? { [] },
            clipboardAsyncReader: clipboardAsyncReader,
            clipboardCountReader: clipboardCountReader ?? { 0 },
            userPasswordReader: userPasswordReader ?? { _ in nil },
            userPasswordAuthentication: userPasswordAuthentication ?? { false },
            sshCredentials: sshCredentials,
            sshKeychain: sshKeychain ?? devices.sshCredentialStore,
            thumbnailStore: thumbnailStore ?? (try! ThumbnailStore.makeTemporary()),
            curtainRecoveryStore: curtainRecoveryStore ?? CurtainRecoveryStore()
        )
    }
}

/// Ordinary tests never initialize shared preferences or a system secret store.
/// Explicitly supplied suites/backends still let persistence and failure tests
/// exercise the original DeviceStore implementation and assertions.
enum TestStorage {
    static func make(userDefaults: UserDefaults? = nil, legacySources: [UserDefaults] = [],
                     keychain: KeychainStore? = nil, passwordStore: (any DevicePasswordStore)? = nil,
                     sshKeychain: SSHKeychainStore? = nil) -> DeviceStore {
        let lease = userDefaults == nil ? TestDefaultsLease() : nil
        let defaults = userDefaults ?? lease!.defaults
        let passwords = keychain ?? KeychainStore(legacyServiceName: nil,
                                                  backend: TestKeychainBackend(defaultsLease: lease))
        let ssh = sshKeychain ?? SSHKeychainStore(backend: TestSSHSecretBackend(defaultsLease: lease))
        return DeviceStore(userDefaults: defaults, legacySources: legacySources,
                           passwordStore: passwordStore ?? passwords, sshKeychain: ssh)
    }

    static func sshKeychain() -> SSHKeychainStore {
        SSHKeychainStore(backend: TestSSHSecretBackend())
    }
}

final class TestDefaultsLease: @unchecked Sendable {
    let suite = "test.aetherscreens.session." + UUID().uuidString
    let defaults: UserDefaults
    init() { defaults = UserDefaults(suiteName: suite)! }
    deinit { defaults.removePersistentDomain(forName: suite) }
}

final class TestKeychainBackend: KeychainSecretBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: [String: Data]] = [:]
    private let defaultsLease: TestDefaultsLease?
    init(defaultsLease: TestDefaultsLease? = nil) { self.defaultsLease = defaultsLease }
    func read(service: String, key: String) -> Data? {
        lock.lock(); defer { lock.unlock() }; return values[service]?[key]
    }
    func write(_ data: Data, service: String, key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }; values[service, default: [:]][key] = data; return true
    }
    func delete(service: String, key: String) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        return values[service]?.removeValue(forKey: key) == nil ? errSecItemNotFound : errSecSuccess
    }
}

final class TestSSHSecretBackend: SSHSecretBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private let defaultsLease: TestDefaultsLease?
    init(defaultsLease: TestDefaultsLease? = nil) { self.defaultsLease = defaultsLease }
    func read(account: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }; return values[account]
    }
    func write(_ data: Data, account: String) throws {
        lock.lock(); defer { lock.unlock() }; values[account] = data
    }
    func insert(_ data: Data, account: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard values[account] == nil else { throw SSHKeychainStore.Failure.keychain(errSecDuplicateItem) }
        values[account] = data
    }
    func delete(account: String) throws {
        lock.lock(); defer { lock.unlock() }; values.removeValue(forKey: account)
    }
}
