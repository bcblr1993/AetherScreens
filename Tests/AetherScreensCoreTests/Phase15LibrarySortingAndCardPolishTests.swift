import XCTest
import CoreGraphics
@testable import AetherScreensCore

final class Phase15LibrarySortingAndCardPolishTests: XCTestCase {

    @MainActor
    func testLibrarySortOrderPersistenceAndSortingBehavior() throws {
        let suiteName = "Phase15Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DeviceStore(userDefaults: defaults)
        let now = Date()
        let devZ = RemoteDevice(
            name: "Zulu Mac",
            host: "10.0.0.3",
            port: 5900,
            deviceType: .mac,
            remoteProtocol: .rfb,
            lastConnected: now.addingTimeInterval(-3600),
            isFavorite: false
        )
        let devA = RemoteDevice(
            name: "Alpha Win",
            host: "10.0.0.1",
            port: 3389,
            deviceType: .windows,
            remoteProtocol: .rdp,
            lastConnected: now.addingTimeInterval(-60),
            isFavorite: false
        )
        let devM = RemoteDevice(
            name: "Mike Linux",
            host: "10.0.0.2",
            port: 5900,
            deviceType: .linux,
            remoteProtocol: .rfb,
            lastConnected: nil,
            isFavorite: true
        )
        store.addDevice(devZ)
        store.addDevice(devA)
        store.addDevice(devM)

        let vm = DeviceListViewModel(store: store, userDefaults: defaults)

        // 1. Sort by Name
        vm.sortOrder = .name
        XCTAssertEqual(vm.filteredDevices.map(\.name), ["Alpha Win", "Mike Linux", "Zulu Mac"])

        // 2. Sort by Recently Connected (most recent first, nil last)
        vm.sortOrder = .lastConnected
        XCTAssertEqual(vm.filteredDevices.map(\.name), ["Alpha Win", "Zulu Mac", "Mike Linux"])

        // 3. Sort by Favorites First (then by name)
        vm.sortOrder = .favoritesFirst
        XCTAssertEqual(vm.filteredDevices.map(\.name), ["Mike Linux", "Alpha Win", "Zulu Mac"])

        // 4. Sort by Protocol (RDP vs RFB, then by name)
        vm.sortOrder = .protocolType
        XCTAssertEqual(vm.filteredDevices.map(\.name), ["Alpha Win", "Mike Linux", "Zulu Mac"])

        // Verify persistence across new ViewModel instance
        let vmReloaded = DeviceListViewModel(store: store, userDefaults: defaults)
        XCTAssertEqual(vmReloaded.sortOrder, .protocolType)
    }

    func testAuxiliaryDisplayCoordinateMapperWithLetterboxing() throws {
        // Secondary display at x=1920, y=0, width=1920, height=1080 (16:9)
        let displayBounds = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        // Window view is 960x600 (16:10 -> 30px top and 30px bottom letterbox bars around 960x540 content)
        let viewSize = CGSize(width: 960, height: 600)

        // Click in the top letterbox bar (y = 15) should return nil
        XCTAssertNil(
            AuxiliaryDisplayCoordinateMapper.mapToRemoteDesktop(
                pointInView: CGPoint(x: 480, y: 15),
                viewSize: viewSize,
                displayBounds: displayBounds
            )
        )

        // Click at exact center of view (480, 300) -> center of secondary display (1920 + 960 = 2880, 540)
        let centerMapped = try XCTUnwrap(
            AuxiliaryDisplayCoordinateMapper.mapToRemoteDesktop(
                pointInView: CGPoint(x: 480, y: 300),
                viewSize: viewSize,
                displayBounds: displayBounds
            )
        )
        XCTAssertEqual(centerMapped.x, 2880, accuracy: 0.5)
        XCTAssertEqual(centerMapped.y, 540, accuracy: 0.5)

        // Click at top-left of fitted content (0, 30) -> origin of secondary display (1920, 0)
        let topLeftMapped = try XCTUnwrap(
            AuxiliaryDisplayCoordinateMapper.mapToRemoteDesktop(
                pointInView: CGPoint(x: 0, y: 30),
                viewSize: viewSize,
                displayBounds: displayBounds
            )
        )
        XCTAssertEqual(topLeftMapped.x, 1920, accuracy: 0.5)
        XCTAssertEqual(topLeftMapped.y, 0, accuracy: 0.5)
    }
}
