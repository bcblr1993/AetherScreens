import XCTest
@testable import AetherScreensCore

final class CurtainModeManagerTests: XCTestCase {

    func testInitialCurtainInactive() {
        let manager = CurtainModeManager()
        XCTAssertFalse(manager.isCurtainActive)
    }

    func testToggleCurtain() {
        let manager = CurtainModeManager()
        var callbackReceived = false
        var stateFromCallback = false

        manager.onCurtainStateChanged = { active in
            callbackReceived = true
            stateFromCallback = active
        }

        manager.toggleCurtain()
        XCTAssertTrue(manager.isCurtainActive)
        XCTAssertTrue(callbackReceived)
        XCTAssertTrue(stateFromCallback)

        manager.toggleCurtain()
        XCTAssertFalse(manager.isCurtainActive)
        XCTAssertFalse(stateFromCallback)
    }

    func testSetCurtainExplicitly() {
        let manager = CurtainModeManager()
        manager.setCurtain(active: true)
        XCTAssertTrue(manager.isCurtainActive)

        manager.setCurtain(active: false)
        XCTAssertFalse(manager.isCurtainActive)
    }
}
