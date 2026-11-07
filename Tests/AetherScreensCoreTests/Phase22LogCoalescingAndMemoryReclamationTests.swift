import XCTest
import Metal
@testable import AetherScreensCore

final class Phase22LogCoalescingAndMemoryReclamationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AppLogger.shared.clear()
    }

    override func tearDown() {
        AppLogger.shared.clear()
        super.tearDown()
    }

    @MainActor
    func testAppLoggerClearPreventsResurrectionFromPendingBackgroundLogsAndExtractsCategories() async {
        let logger = AppLogger.shared
        logger.clear()

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                group.addTask {
                    logger.info("Background event \(index)", category: index % 2 == 0 ? "RFB" : "RDP")
                }
            }
        }

        // Immediately clear on the main thread right after background logging finishes.
        // Previously, unstructured Tasks captured stale `snapshot` arrays and overwrote `entries` after `clear()`.
        logger.clear()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(logger.entries.isEmpty, "Cleared logger must not resurrect stale snapshots from earlier background tasks")
        XCTAssertEqual(logger.exportLogs(), "")

        logger.info("Handshake started", category: "RFB")
        logger.warning("Slow link detected", category: "Network")
        logger.error("Auth rejected", category: "Auth")

        XCTAssertEqual(logger.availableCategories, ["Auth", "Network", "RFB"])
        let rfbOnly = logger.exportLogs(category: "RFB")
        XCTAssertTrue(rfbOnly.contains("Handshake started"))
        XCTAssertFalse(rfbOnly.contains("Slow link detected"))
    }

    func testFramebufferReclaimStorageShrinksLarge4KBufferToMinimalFootprint() {
        let fb = Framebuffer(width: 3840, height: 2160)
        XCTAssertEqual(fb.allocatedByteCount, 3840 * 2160 * 4)

        fb.reclaimStorage()

        XCTAssertEqual(fb.width, 1)
        XCTAssertEqual(fb.height, 1)
        XCTAssertEqual(fb.allocatedByteCount, 4)
    }

    func testMetalScreenRendererReleaseSessionResourcesFreesTextureAndUploadPool() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer(),
              let renderer = MetalScreenRenderer(device: device) else {
            throw XCTSkip("Metal device unavailable")
        }

        let fb = Framebuffer(width: 640, height: 480)
        renderer.framebuffer = fb
        renderer.setUploadBufferCachingEnabled(true)

        let uploaded = renderer.encodeFramebufferUpload(framebuffer: fb, commandBuffer: commandBuffer, shouldUpload: true)
        XCTAssertNotNil(uploaded)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        XCTAssertNotNil(renderer.texture)
        XCTAssertGreaterThan(renderer.cachedUploadBufferBytes, 0)

        renderer.releaseSessionResources()

        XCTAssertNil(renderer.texture)
        XCTAssertEqual(renderer.cachedUploadBufferBytes, 0)
    }

    #if os(macOS)
    @MainActor
    func testSessionWindowManagerClosesAuxiliaryDisplayWindowsWhenPrimarySessionCloses() {
        let manager = SessionWindowManager.shared
        let device = RemoteDevice(name: "Dual Display Mac", host: "10.0.0.42", port: 5900)
        let session = SessionViewModel(device: device, password: nil, isTemporary: true)

        let sessionID = manager.open(session, reuseExisting: false)
        let display1 = DisplayInfo(id: 1, name: "Display 1", bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let display2 = DisplayInfo(id: 2, name: "Display 2", bounds: CGRect(x: 1920, y: 0, width: 1920, height: 1080))

        manager.openAuxiliaryDisplayWindow(for: session, display: display1)
        manager.openAuxiliaryDisplayWindow(for: session, display: display2)
        XCTAssertEqual(manager.auxiliaryWindowCount(for: session.device.id), 2)

        manager.close(sessionID)
        XCTAssertEqual(manager.auxiliaryWindowCount(for: session.device.id), 0)
    }
    #endif
}
