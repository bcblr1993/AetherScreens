import XCTest
import Metal
@testable import AetherScreensCore

final class MetalScreenRendererTests: XCTestCase {

    func testIncrementalGPUUploadsPreservePixelsWithoutUploadingUnchangedDesktop() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Requires a Metal device") }
        let renderer = try XCTUnwrap(MetalScreenRenderer(device: device))
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let fb = Framebuffer(width: 3840, height: 2160)
        func upload(_ expected: Int, shouldUpload: Bool = true) throws {
            let command = try XCTUnwrap(queue.makeCommandBuffer())
            XCTAssertEqual(renderer.encodeFramebufferUpload(framebuffer: fb, commandBuffer: command, shouldUpload: shouldUpload), expected)
            command.commit(); command.waitUntilCompleted()
            XCTAssertNil(command.error)
        }
        func pixel(_ x: Int, _ y: Int) throws -> [UInt8] {
            let command = try XCTUnwrap(queue.makeCommandBuffer())
            let buffer = try XCTUnwrap(device.makeBuffer(length: 256, options: .storageModeShared))
            let encoder = try XCTUnwrap(command.makeBlitCommandEncoder())
            encoder.copy(from: try XCTUnwrap(renderer.texture), sourceSlice: 0, sourceLevel: 0,
                         sourceOrigin: MTLOrigin(x: x, y: y, z: 0), sourceSize: MTLSize(width: 1, height: 1, depth: 1),
                         to: buffer, destinationOffset: 0, destinationBytesPerRow: 256, destinationBytesPerImage: 0)
            encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
            XCTAssertNil(command.error)
            return Array(UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: UInt8.self), count: 4))
        }
        try upload(3840 * 2160 * 4)
        try upload(0)
        fb.updateRect(x: 97, y: 123, width: 1, height: 1, rawData: Data([11, 22, 33, 255]))
        try upload(0, shouldUpload: false)
        try upload(4)
        XCTAssertEqual(try pixel(97, 123), [11, 22, 33, 255])
        XCTAssertEqual(try pixel(98, 123), [0, 0, 0, 0])
        fb.copyRect(srcX: 97, srcY: 123, dstX: 199, dstY: 299, width: 1, height: 1)
        try upload(4)
        XCTAssertEqual(try pixel(199, 299), [11, 22, 33, 255])
        try upload(0)
        fb.resize(newWidth: 8, newHeight: 8)
        try upload(8 * 8 * 4, shouldUpload: false)
        XCTAssertEqual(try pixel(0, 0), [0, 0, 0, 0])
    }

    func testQueuedGPUFramesRetainTheirOwnPixelsUntilExecution() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Requires a Metal device") }
        let renderer = try XCTUnwrap(MetalScreenRenderer(device: device))
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let event = try XCTUnwrap(device.makeSharedEvent())
        defer { event.signaledValue = 1 }
        let fb = Framebuffer(width: 16, height: 16)
        var snapshots: [MTLBuffer] = []
        var last: MTLCommandBuffer?
        for value in 1...24 {
            fb.updateRect(x: 2, y: 3, width: 1, height: 1, rawData: Data([UInt8(value), 10, 20, 255]))
            let command = try XCTUnwrap(queue.makeCommandBuffer())
            if value == 1 { command.encodeWaitForEvent(event, value: 1) }
            XCTAssertEqual(renderer.encodeFramebufferUpload(framebuffer: fb, commandBuffer: command), value == 1 ? 1024 : 4)
            let buffer = try XCTUnwrap(device.makeBuffer(length: 256, options: .storageModeShared))
            let encoder = try XCTUnwrap(command.makeBlitCommandEncoder())
            encoder.copy(from: try XCTUnwrap(renderer.texture), sourceSlice: 0, sourceLevel: 0,
                         sourceOrigin: MTLOrigin(x: 2, y: 3, z: 0), sourceSize: MTLSize(width: 1, height: 1, depth: 1),
                         to: buffer, destinationOffset: 0, destinationBytesPerRow: 256, destinationBytesPerImage: 0)
            encoder.endEncoding(); command.commit()
            snapshots.append(buffer); last = command
        }
        XCTAssertEqual(renderer.cachedUploadBufferBytes, 0, "A blocked GPU must retain exclusive staging leases")
        event.signaledValue = 1
        try XCTUnwrap(last).waitUntilCompleted()
        let recycled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in renderer.cachedUploadBufferBytes > 0 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [recycled], timeout: 3), .completed)
        XCTAssertNil(last?.error)
        for (index, buffer) in snapshots.enumerated() {
            let pixel = Array(UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: UInt8.self), count: 4))
            XCTAssertEqual(pixel, [UInt8(index + 1), 10, 20, 255], "Queued frames must not read a later CPU update")
        }
    }

    func testIndependentTexturesAndSameSizeFramebufferReplacement() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Requires a Metal device") }
        let first = try XCTUnwrap(MetalScreenRenderer(device: device))
        let second = try XCTUnwrap(MetalScreenRenderer(device: device))
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let fb = Framebuffer(width: 8, height: 8)
        func upload(_ renderer: MetalScreenRenderer, _ source: Framebuffer, _ expected: Int) throws {
            let command = try XCTUnwrap(queue.makeCommandBuffer())
            XCTAssertEqual(renderer.encodeFramebufferUpload(framebuffer: source, commandBuffer: command), expected)
            command.commit(); command.waitUntilCompleted(); XCTAssertNil(command.error)
        }
        try upload(first, fb, 256)
        try upload(second, fb, 256)
        fb.updateRect(x: 1, y: 1, width: 1, height: 1, rawData: Data([7, 8, 9, 255]))
        try upload(first, fb, 4)
        try upload(second, fb, 4)
        let replacement = Framebuffer(width: 8, height: 8)
        replacement.updateRect(x: 1, y: 1, width: 1, height: 1, rawData: Data([10, 11, 12, 255]))
        try upload(first, replacement, 256)
        try upload(first, replacement, 0)
        try upload(second, fb, 0)
    }

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
