import XCTest
import Combine
@testable import AetherScreensCore

final class MultiDisplayManagerTests: XCTestCase {
    private var layout: RFBDisplayLayout {
        .init(width: 3840, height: 1440, screens: [
            .init(id: 0, x: 0, y: 360, width: 1920, height: 1080, flags: 0),
            .init(id: UInt32.max, x: 1920, y: 0, width: 1920, height: 1440, flags: 7)
        ])
    }

    func testUltrawideFramebufferDoesNotInventMonitors() {
        let manager = MultiDisplayManager()
        manager.updateFromFramebuffer(width: 5120, height: 1440)
        XCTAssertEqual(manager.availableDisplays.count, 1)
        XCTAssertEqual(manager.currentDisplay?.name, "All Displays")
        XCTAssertEqual(manager.currentDisplay?.resolutionDescription, "5120 × 1440")
        manager.selectDisplay(id: 2)
        XCTAssertEqual(manager.selectedDisplayId, 0)
    }

    func testActualServerIDsAndLayoutSurviveFramebufferPublication() {
        let manager = MultiDisplayManager()
        manager.updateFromLayout(layout)
        XCTAssertEqual(manager.availableDisplays.map(\.id), [0, 1, Int(UInt32.max) + 1])
        XCTAssertEqual(manager.availableDisplays.map(\.isMain), [false, false, false])
        manager.selectDisplay(id: Int(UInt32.max) + 1)
        manager.updateFromFramebuffer(width: 3840, height: 1440)
        XCTAssertEqual(manager.currentDisplay?.bounds.minX, 1920)
        XCTAssertEqual(manager.availableDisplays.count, 3)
        let point = manager.translateCoordinates(x: 100, y: 200, remoteTotalWidth: 3840, remoteTotalHeight: 1440)
        XCTAssertEqual(point.0, 2020)
        XCTAssertEqual(point.1, 200)
    }

    func testCoordinatesStayInsideSelectedMonitorAndFramebuffer() {
        let manager = MultiDisplayManager()
        manager.updateFromLayout(layout)
        manager.selectDisplay(id: 1)
        let outside = manager.translateCoordinates(x: 9999, y: -500, remoteTotalWidth: 3840, remoteTotalHeight: 1440)
        XCTAssertEqual(outside.0, 1919)
        XCTAssertEqual(outside.1, 360)
        manager.selectDisplay(id: 0)
        let edge = manager.translateCoordinates(x: 3840, y: 1440, remoteTotalWidth: 3840, remoteTotalHeight: 1440)
        XCTAssertEqual(edge.0, 3839)
        XCTAssertEqual(edge.1, 1439)
    }

    func testLayoutMoveRemovalAndReconnectUpdateSelectionWithoutDeadlock() {
        let manager = MultiDisplayManager()
        manager.updateFromLayout(layout)
        manager.selectDisplay(id: 1)
        let selected = expectation(description: "Moved monitor and removed monitor callbacks")
        selected.expectedFulfillmentCount = 2
        manager.onDisplaySelected = { display in
            XCTAssertEqual(display, manager.currentDisplay)
            selected.fulfill()
        }
        let subscription = manager.$availableDisplays.sink { _ in _ = manager.currentDisplay }
        defer { subscription.cancel() }
        manager.updateFromLayout(.init(width: 3840, height: 1440, screens: [
            .init(id: 0, x: 1920, y: 0, width: 1920, height: 1080, flags: 0)
        ]))
        XCTAssertEqual(manager.currentDisplay?.bounds.minX, 1920)
        manager.updateFromLayout(.init(width: 3840, height: 1440, screens: []))
        XCTAssertEqual(manager.selectedDisplayId, 0)
        wait(for: [selected], timeout: 1)
        manager.onDisplaySelected = nil
        manager.updateFromLayout(layout)
        manager.selectDisplay(id: 1)
        manager.reset(width: 3840, height: 1440)
        XCTAssertEqual(manager.availableDisplays.count, 1)
        XCTAssertEqual(manager.selectedDisplayId, 0)
    }
}
