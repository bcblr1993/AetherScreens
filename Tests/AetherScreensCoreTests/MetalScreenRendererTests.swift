import XCTest
import Metal
@testable import AetherScreensCore

final class MetalScreenRendererTests: XCTestCase {

    func testSelectedMonitorTextureCoordinatesUseActualBounds() {
        XCTAssertEqual(MetalScreenRenderer.textureRegion(rect: CGRect(x: 320, y: 0, width: 320, height: 360), width: 640, height: 360), SIMD4(0.5, 0, 0.5, 1))
        XCTAssertEqual(MetalScreenRenderer.textureRegion(rect: CGRect(x: 0, y: 360, width: 1920, height: 1080), width: 3840, height: 1440), SIMD4(0, 0.25, 0.5, 0.75))
        XCTAssertEqual(MetalScreenRenderer.textureRegion(rect: nil, width: 640, height: 360), SIMD4(0, 0, 1, 1))
    }

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
