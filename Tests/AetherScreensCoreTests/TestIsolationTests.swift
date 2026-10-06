import XCTest
@testable import AetherScreensCore

@MainActor
final class TestIsolationTests: XCTestCase {
    func testDefaultSessionStoresKeepDevicesPasswordsAndKeyboardPreferencesSeparate() {
        let first = TestStorage.make()
        let second = TestStorage.make()
        let device = RemoteDevice(name: "Private test library", host: "fixture.invalid")
        first.addDevice(device, password: "synthetic-private-store-only")
        XCTAssertEqual(first.getPassword(for: device), "synthetic-private-store-only")
        XCTAssertTrue(second.devicesSnapshot().isEmpty)
        second.addDevice(device)
        XCTAssertNil(second.getPassword(for: device))

        let keyboards = KeyboardToolbarStore(defaults: first.synchronizationDefaults)
        var configuration = KeyboardToolbarConfiguration()
        var hardware = configuration.hardwareKeyboard ?? HardwareKeyboardConfiguration()
        hardware.repeatEnabled = false
        configuration.hardwareKeyboard = hardware
        keyboards.save(configuration, for: device.id)
        let firstSession = TestSession.make(device: device, password: nil, deviceStore: first)
        let secondSession = TestSession.make(device: device, password: nil, deviceStore: second)
        XCTAssertEqual(firstSession.keyboardConfiguration, configuration)
        let defaults = KeyboardToolbarConfiguration()
        XCTAssertEqual(secondSession.keyboardConfiguration.size, defaults.size)
        XCTAssertEqual(secondSession.keyboardConfiguration.position, defaults.position)
        XCTAssertEqual(secondSession.keyboardConfiguration.items.map(\.action), defaults.items.map(\.action))
        XCTAssertEqual(secondSession.keyboardConfiguration.items.map(\.isVisible), defaults.items.map(\.isVisible))
        XCTAssertEqual(secondSession.keyboardConfiguration.hardwareKeyboard, defaults.hardwareKeyboard)
        XCTAssertEqual(secondSession.keyboardConfiguration.pencilDoubleTapAction, defaults.pencilDoubleTapAction)
        XCTAssertEqual(secondSession.keyboardConfiguration.pencilSqueezeAction, defaults.pencilSqueezeAction)
    }

    func testSessionInitializationUsesOnlyTheInjectedClipboardCountReader() {
        var reads = 0
        let session = TestSession.make(device: RemoteDevice(name: "Private clipboard", host: "fixture.invalid"),
            password: nil, clipboardCountReader: { reads += 1; return 17 })
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(session.client.state, .disconnected)
    }
}
