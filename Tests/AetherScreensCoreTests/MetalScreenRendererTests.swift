import XCTest
import Metal
@testable import AetherScreensCore

final class MetalScreenRendererTests: XCTestCase {

    func testMetalRendererInitializationOnAppleSilicon() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            // In headless CI without GPU, skip gracefully
            return
        }

        let renderer = MetalScreenRenderer(device: device)
        XCTAssertNotNil(renderer)
        XCTAssertEqual(renderer?.device.name, device.name)

        let fb = Framebuffer(width: 800, height: 600)
        renderer?.framebuffer = fb
        renderer?.notifyFrameUpdated()
    }
}
