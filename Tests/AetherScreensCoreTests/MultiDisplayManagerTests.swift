import XCTest
@testable import AetherScreensCore

final class MultiDisplayManagerTests: XCTestCase {

    func testInitialDisplaySetup() {
        let manager = MultiDisplayManager()
        XCTAssertEqual(manager.availableDisplays.count, 1)
        XCTAssertEqual(manager.selectedDisplayId, 0)
        XCTAssertEqual(manager.currentDisplay?.name, "All Displays")
    }

    func testSingleMonitorUpdate() {
        let manager = MultiDisplayManager()
        // Single display: 1920x1080
        manager.updateFromFramebuffer(width: 1920, height: 1080)
        XCTAssertEqual(manager.availableDisplays.count, 1)
        XCTAssertEqual(manager.availableDisplays.first?.name, "Main Display")
        XCTAssertEqual(manager.availableDisplays.first?.resolutionDescription, "1920 × 1080")
    }

    func testMultiMonitorAutoDetection() {
        let manager = MultiDisplayManager()
        // Dual monitor: 3840x1080 (width > height * 2)
        manager.updateFromFramebuffer(width: 3840, height: 1080)
        XCTAssertEqual(manager.availableDisplays.count, 3)

        XCTAssertEqual(manager.availableDisplays[0].name, "All Displays")
        XCTAssertEqual(manager.availableDisplays[1].name, "Display 1 (Left)")
        XCTAssertEqual(manager.availableDisplays[2].name, "Display 2 (Right)")

        // Select Display 2
        var selectedInfo: DisplayInfo?
        manager.onDisplaySelected = { display in
            selectedInfo = display
        }

        manager.selectDisplay(id: 2)
        XCTAssertEqual(manager.selectedDisplayId, 2)
        XCTAssertEqual(selectedInfo?.name, "Display 2 (Right)")
        XCTAssertEqual(selectedInfo?.bounds.origin.x, 1920)
    }

    func testCoordinateTranslation() {
        let manager = MultiDisplayManager()
        manager.updateFromFramebuffer(width: 3840, height: 1080)

        // All Displays (id: 0) -> Coordinates should map directly without offset
        manager.selectDisplay(id: 0)
        let (allX, allY) = manager.translateCoordinates(x: 500, y: 300, remoteTotalWidth: 3840, remoteTotalHeight: 1080)
        XCTAssertEqual(allX, 500)
        XCTAssertEqual(allY, 300)

        // Display 2 (Right, origin.x = 1920) -> Local (100, 200) should translate to (2020, 200)
        manager.selectDisplay(id: 2)
        let (disp2X, disp2Y) = manager.translateCoordinates(x: 100, y: 200, remoteTotalWidth: 3840, remoteTotalHeight: 1080)
        XCTAssertEqual(disp2X, 2020)
        XCTAssertEqual(disp2Y, 200)
    }
}
