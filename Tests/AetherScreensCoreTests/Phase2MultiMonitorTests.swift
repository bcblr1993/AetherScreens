import XCTest
import CoreGraphics
@testable import AetherScreensCore

final class Phase2MultiMonitorTests: XCTestCase {

    func testVirtualSplitModeTwoHorizontalCreatesLeftAndRightDisplaysAndMapsCoordinates() {
        let manager = MultiDisplayManager()
        manager.updateFromFramebuffer(width: 3840, height: 1080)
        XCTAssertEqual(manager.availableDisplays.count, 1)
        XCTAssertEqual(manager.virtualSplitMode, .none)

        // Enable 2x horizontal split for dual-monitor combined VNC desktop
        manager.setVirtualSplitMode(.twoHorizontal)
        XCTAssertEqual(manager.virtualSplitMode, .twoHorizontal)
        XCTAssertEqual(manager.availableDisplays.count, 3)
        XCTAssertEqual(manager.availableDisplays[0].bounds, CGRect(x: 0, y: 0, width: 3840, height: 1080))
        XCTAssertEqual(manager.availableDisplays[1].bounds, CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(manager.availableDisplays[2].bounds, CGRect(x: 1920, y: 0, width: 1920, height: 1080))

        // Select right display (id == 2) and verify coordinate translation
        manager.selectDisplay(id: 2)
        XCTAssertEqual(manager.selectedDisplayId, 2)
        let translated = manager.translateCoordinates(x: 250, y: 300, remoteTotalWidth: 3840, remoteTotalHeight: 1080)
        XCTAssertEqual(translated.0, 2170)
        XCTAssertEqual(translated.1, 300)

        // Switching back to .none resets to single full display
        manager.setVirtualSplitMode(.none)
        XCTAssertEqual(manager.availableDisplays.count, 1)
        XCTAssertEqual(manager.selectedDisplayId, 0)
    }

    func testVirtualSplitModeThreeHorizontalAndCycleNextDisplay() {
        let manager = MultiDisplayManager()
        manager.updateFromFramebuffer(width: 5760, height: 1080)
        manager.setVirtualSplitMode(.threeHorizontal)

        XCTAssertEqual(manager.availableDisplays.count, 4)
        XCTAssertEqual(manager.availableDisplays[1].bounds, CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(manager.availableDisplays[2].bounds, CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(manager.availableDisplays[3].bounds, CGRect(x: 3840, y: 0, width: 1920, height: 1080))

        XCTAssertEqual(manager.selectedDisplayId, 0)
        manager.cycleNextDisplay()
        XCTAssertEqual(manager.selectedDisplayId, 1)
        manager.cycleNextDisplay()
        XCTAssertEqual(manager.selectedDisplayId, 2)
        manager.cycleNextDisplay()
        XCTAssertEqual(manager.selectedDisplayId, 3)
        manager.cycleNextDisplay()
        XCTAssertEqual(manager.selectedDisplayId, 0)
    }
}
