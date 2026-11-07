import XCTest
@testable import AetherScreensCore

final class Phase19CurtainModePerDeviceTests: XCTestCase {

    func testRemoteDeviceCurtainPropertiesRoundTripInJSONAndSyncMetadata() throws {
        let device = RemoteDevice(
            name: "Exec Mac",
            host: "10.0.0.50",
            port: 5900,
            deviceType: .mac,
            curtainOnConnect: true,
            curtainMessage: "Maintenance in progress — do not disturb"
        )

        let encoded = try JSONEncoder().encode(device)
        let decoded = try JSONDecoder().decode(RemoteDevice.self, from: encoded)
        XCTAssertEqual(decoded.curtainOnConnect, true)
        XCTAssertEqual(decoded.curtainMessage, "Maintenance in progress — do not disturb")

        var journal = ComputerSyncJournal()
        let changed = try journal.captureLocalComputers([device])
        XCTAssertTrue(changed)
        let syncedMeta = try XCTUnwrap(journal.computers.first)
        XCTAssertEqual(syncedMeta.curtainOnConnect, true)
        XCTAssertEqual(syncedMeta.curtainMessage, "Maintenance in progress — do not disturb")
    }

    func testCurtainModeManagerActivatesOnConnectWithCustomMessage() {
        let manager = CurtainModeManager()
        XCTAssertFalse(manager.isCurtainActive)
        XCTAssertNil(manager.customMessage)

        let normalDevice = RemoteDevice(name: "Normal Mac", host: "10.0.0.10", curtainOnConnect: false)
        XCTAssertFalse(manager.activateForDeviceConnectIfConfigured(normalDevice))
        XCTAssertFalse(manager.isCurtainActive)

        let curtainDevice = RemoteDevice(
            name: "Private Mac",
            host: "10.0.0.11",
            curtainOnConnect: true,
            curtainMessage: "Remote Admin Session Active"
        )
        XCTAssertTrue(manager.activateForDeviceConnectIfConfigured(curtainDevice))
        XCTAssertTrue(manager.isCurtainActive)
        XCTAssertEqual(manager.customMessage, "Remote Admin Session Active")
        XCTAssertEqual(manager.effectiveNoticeTitle, "Remote Admin Session Active")
    }
}
