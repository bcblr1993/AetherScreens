import XCTest
import CoreGraphics
import ImageIO
@testable import AetherScreensCore

final class Phase1ProductivityTests: XCTestCase {

    func testPasswordKeystrokeSequenceWrapsShiftedCharactersAndAppendsReturn() {
        let seq = MacKeyMap.passwordKeystrokeSequence(for: "aB1!", appendReturn: true)

        // Expected sequence:
        // 'a' (0x61): down, up
        // 'B' (0x42): shiftDown, down, up, shiftUp
        // '1' (0x31): down, up
        // '!' (0x21): shiftDown, down, up, shiftUp
        // Return (0xFF0D): down, up
        let expected: [(key: UInt32, down: Bool)] = [
            (0x0061, true), (0x0061, false),
            (MacKeyMap.shiftLeft, true), (0x0042, true), (0x0042, false), (MacKeyMap.shiftLeft, false),
            (0x0031, true), (0x0031, false),
            (MacKeyMap.shiftLeft, true), (0x0021, true), (0x0021, false), (MacKeyMap.shiftLeft, false),
            (MacKeyMap.return, true), (MacKeyMap.return, false)
        ]

        XCTAssertEqual(seq.count, expected.count)
        for (actual, exp) in zip(seq, expected) {
            XCTAssertEqual(actual.key, exp.key)
            XCTAssertEqual(actual.down, exp.down)
        }
    }

    func testPasswordKeystrokeSequenceWithoutReturn() {
        let seq = MacKeyMap.passwordKeystrokeSequence(for: "x@", appendReturn: false)
        let expected: [(key: UInt32, down: Bool)] = [
            (0x0078, true), (0x0078, false),
            (MacKeyMap.shiftLeft, true), (0x0040, true), (0x0040, false), (MacKeyMap.shiftLeft, false)
        ]
        XCTAssertEqual(seq.count, expected.count)
        for (actual, exp) in zip(seq, expected) {
            XCTAssertEqual(actual.key, exp.key)
            XCTAssertEqual(actual.down, exp.down)
        }
    }

    @MainActor
    func testTypeSavedPasswordInSessionViewModel() async throws {
        let device = RemoteDevice(
            name: "Studio Mac",
            host: "192.0.2.10",
            port: 5900,
            deviceType: .mac,
            remoteProtocol: .rfb,
            authMethod: .vncPassword
        )
        let session = SessionViewModel(device: device, password: "Secret!", isTemporary: true)
        defer { session.endSession() }

        // While disconnected, canTypeSavedPassword is false
        XCTAssertFalse(session.canTypeSavedPassword)

        // Simulate connected state
        session.sessionState = .connected
        session.client.onStateChanged?(.connected)
        let exp = expectation(description: "Connected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { exp.fulfill() }
        await fulfillment(of: [exp], timeout: 1.0)

        XCTAssertTrue(session.canTypeSavedPassword)

        // Observe-only blocks typing password
        session.isObserveOnly = true
        XCTAssertFalse(session.canTypeSavedPassword)
        XCTAssertFalse(session.typeSavedPassword(appendReturn: true))

        session.isObserveOnly = false
        XCTAssertTrue(session.canTypeSavedPassword)
        XCTAssertTrue(session.typeSavedPassword(appendReturn: true))
    }

    @MainActor
    func testCaptureAndSaveScreenshotFullAndCroppedDisplay() throws {
        let device = RemoteDevice(
            name: "Dual Display Mac",
            host: "192.0.2.20",
            port: 5900,
            deviceType: .mac
        )
        let session = SessionViewModel(device: device, password: nil, isTemporary: true)
        defer { session.endSession() }

        session.framebuffer.resize(newWidth: 200, newHeight: 100)
        // Fill framebuffer with solid blue-green pixels
        var pixels = Data(count: 200 * 100 * 4)
        pixels.withUnsafeMutableBytes { raw in
            guard let ptr = raw.baseAddress?.assumingMemoryBound(to: UInt32.self) else { return }
            for i in 0..<(200 * 100) {
                ptr[i] = 0xFF2288CC
            }
        }
        session.framebuffer.updateRect(x: 0, y: 0, width: 200, height: 100, rawData: pixels)

        // 1. Full framebuffer screenshot
        let fullImage = try XCTUnwrap(session.captureScreenshotImage())
        XCTAssertEqual(fullImage.width, 200)
        XCTAssertEqual(fullImage.height, 100)

        // 2. Cropped single-display screenshot (Display 2: right half 100x100)
        session.activeCropRect = CGRect(x: 100, y: 0, width: 100, height: 100)
        let croppedImage = try XCTUnwrap(session.captureScreenshotImage())
        XCTAssertEqual(croppedImage.width, 100)
        XCTAssertEqual(croppedImage.height, 100)

        // 3. Save PNG to temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AetherScreensScreenshotTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let savedURL = try XCTUnwrap(session.saveScreenshot(toDirectory: tempDir))
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedURL.path))
        XCTAssertEqual(savedURL.pathExtension.lowercased(), "png")

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(savedURL as CFURL, nil))
        let loaded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(loaded.width, 100)
        XCTAssertEqual(loaded.height, 100)
    }

    func testRemoteDeviceWakeBeforeConnectCodableAndSyncMetadata() throws {
        let device = RemoteDevice(
            name: "Sleeping Office Mac",
            host: "100.64.1.8",
            port: 5900,
            deviceType: .mac,
            macAddress: "AA:BB:CC:11:22:33",
            wakeBeforeConnect: true
        )
        XCTAssertEqual(device.wakeBeforeConnect, true)

        let encoded = try JSONEncoder().encode(device)
        let decoded = try JSONDecoder().decode(RemoteDevice.self, from: encoded)
        XCTAssertEqual(decoded.wakeBeforeConnect, true)
        XCTAssertEqual(decoded.macAddress, "AA:BB:CC:11:22:33")

        let meta = ComputerSyncMetadata(device: device)
        XCTAssertEqual(meta.wakeBeforeConnect, true)
    }
}
