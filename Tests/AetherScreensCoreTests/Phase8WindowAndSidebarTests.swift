import XCTest
@testable import AetherScreensCore

final class Phase8WindowAndSidebarTests: XCTestCase {

    #if os(macOS)
    @MainActor
    func testCalculateAspectRatioFramePreservesCenterAndClampsToScreen() {
        let current = CGRect(x: 300, y: 250, width: 1120, height: 780)
        let remote16x9 = CGSize(width: 1920, height: 1080)
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let minSize = CGSize(width: 800, height: 560)

        let fitted = SessionWindowManager.calculateAspectRatioFrame(
            currentFrame: current,
            remoteSize: remote16x9,
            visibleScreenFrame: screen,
            minSize: minSize
        )

        let ratio = fitted.width / fitted.height
        XCTAssertEqual(ratio, 16.0 / 9.0, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(fitted.width, minSize.width)
        XCTAssertGreaterThanOrEqual(fitted.height, minSize.height)
        XCTAssertTrue(screen.contains(fitted))
        XCTAssertEqual(fitted.midX, current.midX, accuracy: 1.0)
        XCTAssertEqual(fitted.midY, current.midY, accuracy: 1.0)
    }
    #endif

    @MainActor
    func testDeviceListViewModelTagCounts() throws {
        let suiteName = "Phase8Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DeviceStore(userDefaults: defaults)
        store.addDevice(RemoteDevice(name: "Node 1", host: "10.0.0.1", tags: ["Production", "Mac"]))
        store.addDevice(RemoteDevice(name: "Node 2", host: "10.0.0.2", tags: ["Production", "GPU"]))
        store.addDevice(RemoteDevice(name: "Node 3", host: "10.0.0.3", tags: ["Staging"]))

        let vm = DeviceListViewModel(store: store)
        XCTAssertEqual(vm.allTags, ["GPU", "Mac", "Production", "Staging"])
        XCTAssertEqual(vm.tagCounts["Production"], 2)
        XCTAssertEqual(vm.tagCounts["Mac"], 1)
        XCTAssertEqual(vm.tagCounts["GPU"], 1)
        XCTAssertEqual(vm.tagCounts["Staging"], 1)
    }
}
