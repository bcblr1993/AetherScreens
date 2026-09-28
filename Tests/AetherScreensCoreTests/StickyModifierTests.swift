import XCTest
@testable import AetherScreensCore

@MainActor
final class StickyModifierTests: XCTestCase {

    func testModifierThreeStateTransitions() {
        let device = RemoteDevice(name: "Test Mac", host: "127.0.0.1")
        let vm = SessionViewModel(device: device, password: nil)

        // Initial state: inactive
        XCTAssertEqual(vm.cmdState, .inactive)
        XCTAssertFalse(vm.isCmdActive)

        // First tap: activeOnce
        vm.cycleCmd()
        XCTAssertEqual(vm.cmdState, .activeOnce)
        XCTAssertTrue(vm.isCmdActive)

        // Second tap: locked 🔒
        vm.cycleCmd()
        XCTAssertEqual(vm.cmdState, .locked)
        XCTAssertTrue(vm.isCmdActive)

        // Third tap: back to inactive
        vm.cycleCmd()
        XCTAssertEqual(vm.cmdState, .inactive)
        XCTAssertFalse(vm.isCmdActive)
    }

    func testReleaseAllModifiers() {
        let device = RemoteDevice(name: "Test Mac", host: "127.0.0.1")
        let vm = SessionViewModel(device: device, password: nil)

        vm.cycleCmd()
        vm.cycleOption()
        vm.cycleControl()
        vm.cycleShift()

        XCTAssertTrue(vm.isCmdActive)
        XCTAssertTrue(vm.isOptActive)
        XCTAssertTrue(vm.isCtrlActive)
        XCTAssertTrue(vm.isShiftActive)

        vm.releaseAllModifiers()

        XCTAssertEqual(vm.cmdState, .inactive)
        XCTAssertEqual(vm.optState, .inactive)
        XCTAssertEqual(vm.ctrlState, .inactive)
        XCTAssertEqual(vm.shiftState, .inactive)
    }
}
