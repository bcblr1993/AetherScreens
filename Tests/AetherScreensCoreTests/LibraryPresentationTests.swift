import XCTest
import SwiftUI
@testable import AetherScreensCore

final class LibraryPresentationTests: XCTestCase {
    func testCategoriesMatchSavedComputers() {
        let mac = RemoteDevice(name: "Studio", host: "192.0.2.1", deviceType: .mac, isFavorite: true)
        let windows = RemoteDevice(name: "Office PC", host: "192.0.2.2", port: 3389, deviceType: .windows, remoteProtocol: .rdp)
        var tailnet = RemoteDevice(name: "Laptop", host: "100.80.0.9", deviceType: .mac)
        tailnet.isTailscaleNode = true
        let all = [mac, windows, tailnet]

        XCTAssertEqual(all.filter(DeviceCategory.all.matches).map(\.name), ["Studio", "Office PC", "Laptop"])
        XCTAssertEqual(all.filter(DeviceCategory.favorites.matches).map(\.name), ["Studio"])
        XCTAssertEqual(all.filter(DeviceCategory.mac.matches).map(\.name), ["Studio", "Laptop"])
        XCTAssertEqual(all.filter(DeviceCategory.windows.matches).map(\.name), ["Office PC"])
        XCTAssertEqual(all.filter(DeviceCategory.tailscale.matches).map(\.name), ["Laptop"])
        XCTAssertTrue(all.filter(DeviceCategory.nearby.matches).isEmpty)
    }

    func testEveryCategoryHasLocalizedTitle() {
        let previous = AppLocalization.language
        defer { AppLocalization.select(previous) }
        AppLocalization.select(.simplifiedChinese)
        for category in DeviceCategory.allCases {
            XCTAssertNotEqual(AppLocalization.string(category.rawValue), category.rawValue, category.rawValue)
        }
        XCTAssertEqual(AppLocalization.string(DeviceCategory.windows.rawValue), "Windows 电脑")
    }

    #if os(macOS)
    @MainActor
    func testSessionWindowIsNotResizedByContentIdealSize() {
        let view = SessionWindowManager.makeHostingView(Color.clear.frame(idealWidth: 4000))
        XCTAssertEqual(view.sizingOptions, [.minSize])
    }
    #endif
}
