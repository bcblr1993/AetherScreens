import XCTest
@testable import AetherScreensCore

@MainActor
final class AppLockServiceTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.aetherscreens.applock.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        super.tearDown()
    }

    func testInitialStateDefaultsToUnlockedAndDisabled() {
        let service = AppLockService(userDefaults: userDefaults)
        XCTAssertFalse(service.isLocked)
        XCTAssertFalse(service.isLockEnabled)
        XCTAssertEqual(service.autoLockInterval, .immediately)
    }

    func testEnablingLockPersistsAndCanBeToggled() {
        let service = AppLockService(userDefaults: userDefaults)
        service.isLockEnabled = true
        service.autoLockInterval = .fiveMinutes

        // Recreate service with same defaults
        let restored = AppLockService(userDefaults: userDefaults)
        XCTAssertTrue(restored.isLockEnabled)
        XCTAssertEqual(restored.autoLockInterval, .fiveMinutes)
    }

    func testImmediateLockOnForegrounding() {
        let service = AppLockService(userDefaults: userDefaults)
        service.isLockEnabled = true
        service.autoLockInterval = .immediately

        let backgroundTime = Date()
        service.handleAppDidEnterBackground(date: backgroundTime)

        // Return immediately
        service.handleAppWillEnterForeground(date: backgroundTime.addingTimeInterval(1))
        XCTAssertTrue(service.isLocked)
    }

    func testTimedAutoLockInterval() {
        let service = AppLockService(userDefaults: userDefaults)
        service.isLockEnabled = true
        service.autoLockInterval = .oneMinute

        let backgroundTime = Date()
        service.handleAppDidEnterBackground(date: backgroundTime)

        // 30 seconds later (less than 1 minute) -> should not lock
        service.handleAppWillEnterForeground(date: backgroundTime.addingTimeInterval(30))
        XCTAssertFalse(service.isLocked)

        // 65 seconds later -> should lock
        service.handleAppDidEnterBackground(date: backgroundTime)
        service.handleAppWillEnterForeground(date: backgroundTime.addingTimeInterval(65))
        XCTAssertTrue(service.isLocked)
    }

    func testNeverAutoLockDoesNotLockOnForeground() {
        let service = AppLockService(userDefaults: userDefaults)
        service.isLockEnabled = true
        service.autoLockInterval = .never

        let backgroundTime = Date()
        service.handleAppDidEnterBackground(date: backgroundTime)

        // Even 1 hour later, should not auto-lock
        service.handleAppWillEnterForeground(date: backgroundTime.addingTimeInterval(3600))
        XCTAssertFalse(service.isLocked)
    }

    func testUnlockSuccessUpdatesIsLockedState() async {
        let service = AppLockService(
            userDefaults: userDefaults,
            authEvaluator: { _ in true },
            biometryEvaluator: { .faceID }
        )
        service.isLockEnabled = true
        service.lock()
        XCTAssertTrue(service.isLocked)
        XCTAssertEqual(service.biometryType, .faceID)

        let unlocked = await service.unlock()
        XCTAssertTrue(unlocked)
        XCTAssertFalse(service.isLocked)
    }

    func testUnlockFailureLeavesStateLocked() async {
        let service = AppLockService(
            userDefaults: userDefaults,
            authEvaluator: { _ in false },
            biometryEvaluator: { .touchID }
        )
        service.isLockEnabled = true
        service.lock()
        XCTAssertTrue(service.isLocked)
        XCTAssertEqual(service.biometryType, .touchID)

        let unlocked = await service.unlock()
        XCTAssertFalse(unlocked)
        XCTAssertTrue(service.isLocked)
    }

    func testManualLockTriggersLockOnlyWhenEnabled() {
        let service = AppLockService(userDefaults: userDefaults)
        service.isLockEnabled = false
        service.lock()
        XCTAssertFalse(service.isLocked)

        service.isLockEnabled = true
        service.lock()
        XCTAssertTrue(service.isLocked)
    }
}
