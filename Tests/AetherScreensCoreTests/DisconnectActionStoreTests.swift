import XCTest
@testable import AetherScreensCore

final class DisconnectActionStoreTests: XCTestCase {
    func testHotCornersUseDesktopBoundsAndNeverPressMouseButtons() {
        let corners: [(DisconnectAction, [UInt8])] = [
            (.topLeft, [5, 0, 0, 0, 0, 0]),
            (.topRight, [5, 0, 2, 127, 0, 0]),
            (.bottomLeft, [5, 0, 0, 0, 1, 103]),
            (.bottomRight, [5, 0, 2, 127, 1, 103])
        ]
        for (action, destination) in corners {
            let packet = action.encodedPacket(type: .mac, width: 640, height: 360)
            XCTAssertEqual(packet.count, 12)
            XCTAssertEqual(Array(packet.prefix(6)), [5, 0, 1, 63, 0, 179])
            XCTAssertEqual(Array(packet.suffix(6)), destination)
            XCTAssertTrue(action.encodedPacket(type: .windows, width: 640, height: 360).isEmpty)
            XCTAssertTrue(action.encodedPacket(type: .mac, width: 0, height: 360).isEmpty)
        }
    }

    func testFinalKeyActionsReleaseEveryPressedKeyAndRespectPlatform() {
        for (action, type, expected) in [
            (DisconnectAction.logOut, RemoteDevice.DeviceType.mac, [UInt32(0xFFE9), 0xFFE1, 0xFFEB, 113]),
            (.controlAltDelete, .windows, [0xFFE3, 0xFFE9, 0xFFFF])
        ] {
            let packet = Array(action.encodedPacket(type: type, width: 640, height: 360))
            XCTAssertEqual(packet.count, expected.count * 16)
            var keys: [UInt32] = [], down: [Bool] = []
            for offset in stride(from: 0, to: packet.count, by: 8) {
                XCTAssertEqual(packet[offset], 4)
                down.append(packet[offset + 1] == 1)
                keys.append(packet[(offset + 4)..<(offset + 8)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
            }
            XCTAssertEqual(keys, expected + expected.reversed())
            XCTAssertEqual(down, Array(repeating: true, count: expected.count) + Array(repeating: false, count: expected.count))
        }
        XCTAssertTrue(DisconnectAction.controlAltDelete.encodedPacket(type: .mac, width: 640, height: 360).isEmpty)
        XCTAssertTrue(DisconnectAction.none.encodedPacket(type: .mac, width: 640, height: 360).isEmpty)
    }
    func testMissingUnknownAndWrongPlatformPreferencesDoNotExecuteActions() throws {
        let suite = "DisconnectActionTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DisconnectActionStore(defaults: defaults)
        let id = UUID()
        XCTAssertEqual(store.load(for: id, type: .mac), .none)
        defaults.set("future-action", forKey: "aetherscreens.disconnect-action." + id.uuidString)
        XCTAssertEqual(store.load(for: id, type: .mac), .none)
        store.save(.lockScreen, for: id)
        XCTAssertEqual(store.load(for: id, type: .mac), .lockScreen)
        XCTAssertEqual(store.load(for: id, type: .windows), .none)
        store.save(.controlAltDelete, for: id)
        XCTAssertEqual(store.load(for: id, type: .windows), .controlAltDelete)
        XCTAssertEqual(store.load(for: id, type: .mac), .none)
    }

    func testSavedComputerPreferencesRemainIsolatedAcrossReloadAndDeletion() throws {
        let suite = "DisconnectActionTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = UUID(), second = UUID()
        let store = DisconnectActionStore(defaults: defaults)
        store.save(.topRight, for: first)
        store.save(.bottomLeft, for: second)
        let reloaded = DisconnectActionStore(defaults: defaults)
        XCTAssertEqual(reloaded.load(for: first, type: .mac), .topRight)
        XCTAssertEqual(reloaded.load(for: second, type: .mac), .bottomLeft)
        reloaded.remove(for: first)
        XCTAssertEqual(reloaded.load(for: first, type: .mac), .none)
        XCTAssertEqual(reloaded.load(for: second, type: .mac), .bottomLeft)
    }
}
