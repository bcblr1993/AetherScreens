import XCTest
import Combine
@testable import AetherScreensCore

final class MultiDisplayManagerTests: XCTestCase {
    func testRememberedWireIDWaitsForServerLayoutAndSurvivesReconnect() {
        let manager = MultiDisplayManager(preferredDisplayID: UInt32.max)
        manager.updateFromFramebuffer(width: 3840, height: 1440)
        XCTAssertEqual(manager.selectedDisplayId, 0, "A preference cannot invent a monitor before the server reports it")
        XCTAssertEqual(manager.availableDisplays.count, 1)
        manager.updateFromLayout(layout)
        XCTAssertEqual(manager.selectedDisplayId, Int(UInt32.max) + 1)
        manager.reset(width: 3840, height: 1440)
        XCTAssertEqual(manager.selectedDisplayId, 0)
        manager.updateFromLayout(layout)
        XCTAssertEqual(manager.selectedDisplayId, Int(UInt32.max) + 1)
        let point = manager.translateCoordinates(x: 100, y: 200, remoteTotalWidth: 3840, remoteTotalHeight: 1440)
        XCTAssertEqual(point.0, 2020)
        XCTAssertEqual(point.1, 200)
    }

    func testAbsentRememberedDisplayUsesAllAndExplicitAllClearsPreference() {
        let manager = MultiDisplayManager(preferredDisplayID: 0)
        manager.updateFromLayout(.init(width: 3840, height: 1440, screens: []))
        XCTAssertEqual(manager.selectedDisplayId, 0)
        manager.updateFromLayout(layout)
        XCTAssertEqual(manager.selectedDisplayId, 1, "Wire ID zero is a real monitor, not All Displays")
        manager.updateFromLayout(.init(width: 3840, height: 1440, screens: []))
        XCTAssertEqual(manager.selectedDisplayId, 0)
        manager.selectDisplay(id: 0)
        manager.updateFromLayout(layout)
        XCTAssertEqual(manager.selectedDisplayId, 0, "Explicit All must prevent a later layout from restoring the old preference")
    }

    func testExplicitDisplayChoiceReplacesPreferenceButInvalidChoiceDoesNot() {
        let manager = MultiDisplayManager(preferredDisplayID: UInt32.max)
        manager.updateFromLayout(layout)
        manager.selectDisplay(id: 1)
        manager.selectDisplay(id: -1)
        manager.reset(width: 3840, height: 1440)
        manager.updateFromLayout(layout)
        XCTAssertEqual(manager.selectedDisplayId, 1)
        manager.selectDisplay(id: 0)
        manager.reset(width: 3840, height: 1440)
        manager.updateFromLayout(layout)
        XCTAssertEqual(manager.selectedDisplayId, 0)
    }

    func testNativeMenuUsesActualIDsAndConfirmedSelectionWithoutSecondCrop() throws {
        let manager = MultiDisplayManager()
        let native = try XCTUnwrap(RFBAppleDisplayLayout.parse(AppleDisplayTestPayload.body()))
        manager.updateFromAppleLayout(native)
        XCTAssertEqual(manager.availableDisplays.map(\.id), [0, 1, 23])
        XCTAssertEqual(manager.availableDisplays.map(\.isMain), [false, true, false])
        XCTAssertEqual(manager.availableDisplays.map(\.name), ["All Displays", "Display 1", "Display 2"])
        XCTAssertNil(manager.selectedViewportCropRect)
        let sent = expectation(description: "Native request")
        manager.onNativeDisplaySelection = { id in XCTAssertEqual(id, 22); sent.fulfill(); return true }
        XCTAssertTrue(manager.selectDisplay(id: 23))
        XCTAssertEqual(manager.selectedDisplayId, 0)
        XCTAssertEqual(manager.pendingDisplayId, 23)
        manager.updateFromAppleLayout(try XCTUnwrap(RFBAppleDisplayLayout.parse(AppleDisplayTestPayload.body(selected: 22))))
        XCTAssertEqual(manager.selectedDisplayId, 23)
        XCTAssertNil(manager.selectedViewportCropRect)
        let point = manager.translateCoordinates(x: 4, y: 3, remoteTotalWidth: 8, remoteTotalHeight: 8)
        XCTAssertEqual(point.0, 4)
        XCTAssertEqual(point.1, 3)
        manager.updateFromFramebuffer(width: 8, height: 8)
        XCTAssertEqual(manager.availableDisplays.count, 3)
        manager.finishNativeSelection()
        XCTAssertNil(manager.pendingDisplayId)
        wait(for: [sent], timeout: 1)
    }

    func testNativeRememberedIDWaitsForReportedMonitorAndDoesNotCheckOptimistically() throws {
        let manager = MultiDisplayManager(preferredDisplayID: 22)
        let request = expectation(description: "Restore once per connection")
        request.expectedFulfillmentCount = 2
        manager.onNativeDisplaySelection = { id in XCTAssertEqual(id, 22); request.fulfill(); return true }
        let all = try XCTUnwrap(RFBAppleDisplayLayout.parse(AppleDisplayTestPayload.body()))
        manager.updateFromAppleLayout(all)
        XCTAssertEqual(manager.selectedDisplayId, 0)
        XCTAssertEqual(manager.pendingDisplayId, 23)
        manager.updateFromAppleLayout(all)
        manager.finishNativeSelection()
        manager.reset(width: 16, height: 8)
        XCTAssertEqual(manager.availableDisplays.count, 1)
        manager.updateFromAppleLayout(all)
        wait(for: [request], timeout: 1)
    }

    func testNativeInvalidChoiceAndRefusalDoNotChangeConfirmationOrPreference() throws {
        let manager = MultiDisplayManager()
        let all = try XCTUnwrap(RFBAppleDisplayLayout.parse(AppleDisplayTestPayload.body()))
        manager.updateFromAppleLayout(all)
        manager.onNativeDisplaySelection = { _ in false }
        XCTAssertFalse(manager.selectDisplay(id: 999))
        XCTAssertFalse(manager.selectDisplay(id: 23))
        XCTAssertEqual(manager.selectedDisplayId, 0)
        XCTAssertNil(manager.pendingDisplayId)
        manager.reset(width: 16, height: 8)
        manager.updateFromAppleLayout(all)
        XCTAssertNil(manager.pendingDisplayId)
    }

    func testNativeExplicitAllClearsUnavailablePreferenceForReconnect() throws {
        let manager = MultiDisplayManager(preferredDisplayID: 99)
        let all = try XCTUnwrap(RFBAppleDisplayLayout.parse(AppleDisplayTestPayload.body()))
        manager.updateFromAppleLayout(all)
        XCTAssertTrue(manager.selectDisplay(id: 0))
        manager.reset(width: 8, height: 8)
        let restored = expectation(description: "Explicit All requested")
        manager.onNativeDisplaySelection = { id in XCTAssertNil(id); restored.fulfill(); return true }
        manager.updateFromAppleLayout(try XCTUnwrap(RFBAppleDisplayLayout.parse(AppleDisplayTestPayload.body(selected: 22))))
        wait(for: [restored], timeout: 1)
    }

    func testNativePublishingNeverHoldsSnapshotLockDuringCallbacks() throws {
        let manager = MultiDisplayManager()
        let subscription = manager.$availableDisplays.sink { _ in _ = manager.currentDisplay }
        defer { subscription.cancel() }
        manager.updateFromAppleLayout(try XCTUnwrap(RFBAppleDisplayLayout.parse(AppleDisplayTestPayload.body())))
        manager.onNativeDisplaySelection = { _ in _ = manager.currentDisplay; return true }
        XCTAssertTrue(manager.selectDisplay(id: 23))
        manager.onDisplaySelected = { display in XCTAssertEqual(display, manager.currentDisplay) }
        manager.updateFromAppleLayout(try XCTUnwrap(RFBAppleDisplayLayout.parse(AppleDisplayTestPayload.body(selected: 22))))
        XCTAssertEqual(manager.selectedDisplayId, 23)
    }

    func testNativeCompletionForEarlierChoiceCannotClearNewPendingChoice() throws {
        let manager = MultiDisplayManager()
        manager.updateFromAppleLayout(try XCTUnwrap(RFBAppleDisplayLayout.parse(AppleDisplayTestPayload.body())))
        manager.onNativeDisplaySelection = { _ in true }
        manager.selectDisplay(id: 1)
        manager.selectDisplay(id: 23)
        XCTAssertFalse(manager.finishNativeSelection(id: 0))
        XCTAssertEqual(manager.pendingDisplayId, 23)
        XCTAssertTrue(manager.finishNativeSelection(id: 22))
        XCTAssertNil(manager.pendingDisplayId)
    }

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
