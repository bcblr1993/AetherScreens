import XCTest
import Metal
@testable import AetherScreensCore

@MainActor
final class RemoteDisplayMirrorTests: XCTestCase {
    func testDisplayConnectionNeverStartsMirroringWithoutUserChoiceAndFreshSession() {
        let mirror = RemoteDisplayMirror()
        var requests: [Bool] = []
        mirror.onEnabledChanged = { requests.append($0) }
        mirror.updateAvailability(true)
        mirror.setMirroring(true)
        XCTAssertFalse(mirror.isMirroring, "A display alone must not expose an unready session")
        mirror.updatePresentationAllowed(true)
        XCTAssertFalse(mirror.isMirroring, "Fresh pixels must not automatically opt into mirroring")
        mirror.setMirroring(true)
        XCTAssertTrue(mirror.isMirroring)
        XCTAssertEqual(requests, [true])
        mirror.updateAvailability(false)
        XCTAssertFalse(mirror.isMirroring)
        XCTAssertEqual(requests, [true, false])
        mirror.updateAvailability(true)
        XCTAssertFalse(mirror.isMirroring, "Replugging a display needs a new explicit choice")
    }

    func testSessionHideDisconnectAndStaleSceneCannotRestoreOrStopAnotherPresentation() throws {
        let mirror = RemoteDisplayMirror()
        mirror.updateAvailability(true)
        mirror.updatePresentationAllowed(true)
        mirror.setMirroring(true)
        let framebuffer = Framebuffer(width: 16, height: 16)
        let first = try XCTUnwrap(mirror.beginPresentation(framebuffer: framebuffer))
        mirror.updatePresentationAllowed(false)
        XCTAssertFalse(mirror.isMirroring)
        XCTAssertNil(mirror.beginPresentation(framebuffer: framebuffer))
        mirror.updatePresentationAllowed(true)
        XCTAssertFalse(mirror.isMirroring)
        mirror.setMirroring(true)
        let second = try XCTUnwrap(mirror.beginPresentation(framebuffer: framebuffer))
        XCTAssertNotEqual(first.id, second.id)
        mirror.endPresentation(id: first.id)
        XCTAssertTrue(mirror.isMirroring, "A delayed old scene-disconnect must not stop the new scene")
        mirror.endPresentation(id: second.id)
        XCTAssertFalse(mirror.isMirroring)
    }

    func testMirrorGPUUploadsUseIndependentTexturesAndMetricsForSameChangingFramebuffer() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let primaryMetrics = PerformanceMetrics()
        let primary = try XCTUnwrap(MetalScreenRenderer(device: device, metrics: primaryMetrics))
        let mirror = RemoteDisplayMirror()
        mirror.updateAvailability(true)
        mirror.updatePresentationAllowed(true)
        mirror.setMirroring(true)
        let framebuffer = Framebuffer(width: 16, height: 16)
        primary.framebuffer = framebuffer
        let presentation = try XCTUnwrap(mirror.beginPresentation(framebuffer: framebuffer))
        let external = try XCTUnwrap(presentation.renderer)
        XCTAssertFalse(primary === external)
        XCTAssertFalse(primary.metrics === external.metrics)
        XCTAssertTrue(external.framebuffer === framebuffer)
        func upload(_ renderer: MetalScreenRenderer, expected: Int) throws {
            let command = try XCTUnwrap(renderer.device.makeCommandQueue()?.makeCommandBuffer())
            XCTAssertEqual(renderer.encodeFramebufferUpload(framebuffer: framebuffer, commandBuffer: command), expected)
            command.commit(); command.waitUntilCompleted()
            XCTAssertNil(command.error)
        }
        try upload(primary, expected: 1024)
        try upload(external, expected: 1024)
        XCTAssertFalse(primary.texture === external.texture)
        framebuffer.updateRect(x: 3, y: 5, width: 1, height: 1, rawData: Data([11, 22, 33, 255]))
        try upload(external, expected: 4)
        try upload(primary, expected: 4)
        try upload(external, expected: 0)
        for renderer in [primary, external] {
            let command = try XCTUnwrap(renderer.device.makeCommandQueue()?.makeCommandBuffer())
            let buffer = try XCTUnwrap(renderer.device.makeBuffer(length: 256, options: .storageModeShared))
            let blit = try XCTUnwrap(command.makeBlitCommandEncoder())
            blit.copy(from: try XCTUnwrap(renderer.texture), sourceSlice: 0, sourceLevel: 0,
                      sourceOrigin: MTLOrigin(x: 3, y: 5, z: 0), sourceSize: MTLSize(width: 1, height: 1, depth: 1),
                      to: buffer, destinationOffset: 0, destinationBytesPerRow: 256, destinationBytesPerImage: 0)
            blit.endEncoding(); command.commit(); command.waitUntilCompleted()
            XCTAssertNil(command.error)
            XCTAssertEqual(Array(UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: UInt8.self), count: 4)), [11, 22, 33, 255])
        }
        external.metrics.recordPresentedFrame(at: 1, generation: external.metrics.measurementGeneration)
        XCTAssertEqual(external.metrics.acceptedPresentationCount, 1)
        XCTAssertEqual(primaryMetrics.acceptedPresentationCount, 0, "External output must not inflate interactive FPS")
        mirror.endPresentation(id: presentation.id)
    }

    func testActualSessionVisibilityAndEndRevokeExternalPresentationWithoutChangingViewport() {
        let session = TestSession.make(device: RemoteDevice(name: "Mirror QA", host: "127.0.0.1", port: 1),
                                       password: nil, isTemporary: true)
        session.zoomScale = 2.5
        session.viewOffset = CGSize(width: 30, height: 20)
        let mirror = session.externalDisplayMirror
        // Isolate an already opted-in presentation; no socket, display or clipboard is accessed.
        mirror.updateAvailability(true)
        mirror.updatePresentationAllowed(true)
        mirror.setMirroring(true)
        session.setForegroundSession(false)
        XCTAssertFalse(mirror.isMirroring)
        XCTAssertFalse(mirror.canPresent)
        XCTAssertEqual(session.zoomScale, 2.5)
        XCTAssertEqual(session.viewOffset, CGSize(width: 30, height: 20))
        session.setForegroundSession(true)
        XCTAssertFalse(mirror.isMirroring)
        mirror.updatePresentationAllowed(true)
        mirror.setMirroring(true)
        session.endSession()
        XCTAssertFalse(mirror.isMirroring)
        XCTAssertFalse(mirror.canPresent)
        XCTAssertEqual(session.client.state, .disconnected)
    }
}
