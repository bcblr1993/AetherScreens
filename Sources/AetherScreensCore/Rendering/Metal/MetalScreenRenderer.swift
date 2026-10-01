import Foundation
import Metal
import MetalKit

/// High-performance Metal renderer for remote desktop framebuffers.
/// Capable of rendering at up to 120 FPS on ProMotion displays (iOS & Apple Silicon Mac).
public final class MetalScreenRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {

    public let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private(set) var texture: MTLTexture?
    private weak var attachedView: MTKView?

    public weak var framebuffer: Framebuffer?
    public let metrics: PerformanceMetrics

    private let lock = NSLock()
    private var uploadedRevision: UInt64?
    private weak var textureFramebuffer: Framebuffer?
    private var inFlightFrames = 0
    private var redrawWhenAvailable = false
    private var isDirty: Bool = true
    private var displayScheduled = false
    private var sourceRect: CGRect?

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
    };

    vertex VertexOut screenVertex(uint vid [[vertex_id]], constant float4 &crop [[buffer(0)]]) {
        // Fullscreen quad: 4 vertices (triangle strip)
        float2 positions[4] = {
            float2(-1.0, -1.0),
            float2( 1.0, -1.0),
            float2(-1.0,  1.0),
            float2( 1.0,  1.0)
        };
        // Normalized texture coordinates
        float2 texCoords[4] = {
            float2(0.0, 1.0),
            float2(1.0, 1.0),
            float2(0.0, 0.0),
            float2(1.0, 0.0)
        };
        VertexOut out;
        out.position = float4(positions[vid], 0.0, 1.0);
        out.texCoord = crop.xy + texCoords[vid] * crop.zw;
        return out;
    }

    fragment float4 screenFragment(
        VertexOut in [[stage_in]],
        texture2d<float> screenTexture [[texture(0)]]
    ) {
        constexpr sampler textureSampler(
            address::clamp_to_edge,
            filter::linear
        );
        return screenTexture.sample(textureSampler, in.texCoord);
    }
    """

    public init?(device: MTLDevice? = MTLCreateSystemDefaultDevice(), metrics: PerformanceMetrics = .shared) {
        guard let dev = device, let queue = dev.makeCommandQueue() else {
            return nil
        }
        self.device = dev
        self.commandQueue = queue
        self.metrics = metrics
        super.init()

        setupPipeline()
    }

    private func setupPipeline() {
        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            guard let vertexFunction = library.makeFunction(name: "screenVertex"),
                  let fragmentFunction = library.makeFunction(name: "screenFragment") else {
                return
            }

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

            self.pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("[MetalScreenRenderer] Pipeline setup failed: \(error)")
        }
    }

    /// Mark that the remote framebuffer has new pixel data to upload
    public func notifyFrameUpdated() {
        lock.lock()
        isDirty = true
        let schedule = !displayScheduled
        displayScheduled = true
        lock.unlock()
        guard schedule else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.displayScheduled = false
            self.lock.unlock()
            if let view = self.attachedView { self.requestDisplay(view) }
        }
    }

    /// Change the visible texture region without reallocating the full framebuffer or uploading pixels.
    public func setSourceRect(_ rect: CGRect?) {
        lock.lock()
        let changed = sourceRect != rect
        sourceRect = rect
        lock.unlock()
        if changed, let view = attachedView { requestDisplay(view) }
    }

    static func textureRegion(rect: CGRect?, width: Int, height: Int) -> SIMD4<Float> {
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        let region = rect.map { $0.intersection(full) } ?? full
        guard width > 0, height > 0, !region.isEmpty, !region.isNull else { return SIMD4(0, 0, 1, 1) }
        return SIMD4(Float(region.minX / full.width), Float(region.minY / full.height),
                     Float(region.width / full.width), Float(region.height / full.height))
    }

    public func attach(to view: MTKView) {
        attachedView = view
        requestDisplay(view)
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        requestDisplay(view)
    }

    private func requestDisplay(_ view: MTKView) {
        let invalidate = {
            #if os(macOS)
            view.needsDisplay = true
            #else
            view.setNeedsDisplay()
            #endif
        }
        if Thread.isMainThread { invalidate() }
        else { DispatchQueue.main.async(execute: invalidate) }
    }

    private func beginFrame() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard inFlightFrames < 3 else { redrawWhenAvailable = true; return false }
        inFlightFrames += 1
        return true
    }

    private func completeFrame() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        inFlightFrames -= 1
        let retry = redrawWhenAvailable
        redrawWhenAvailable = false
        return retry
    }

    public func draw(in view: MTKView) {
        guard let pState = pipelineState, let fb = framebuffer else { return }
        // Keep input/UI responsive if the GPU is behind; the next completion redraws the newest state.
        guard beginFrame() else { return }
        guard let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            if completeFrame() { notifyFrameUpdated() }
            return
        }
        lock.lock()
        let dirty = isDirty
        let crop = sourceRect
        isDirty = false
        lock.unlock()
        guard encodeFramebufferUpload(framebuffer: fb, commandBuffer: commandBuffer, shouldUpload: dirty) != nil,
              let tex = texture else {
            lock.lock(); isDirty = true; lock.unlock()
            if completeFrame() { notifyFrameUpdated() }
            return
        }
        commandBuffer.addCompletedHandler { [weak self] completed in
            guard let self else { return }
            let retry = self.completeFrame()
            if completed.status == .error {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.uploadedRevision = nil
                    self.notifyFrameUpdated()
                }
            } else if retry { self.notifyFrameUpdated() }
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            // Finish any already-encoded upload, preserving texture/revision consistency.
            commandBuffer.commit()
            return
        }
        encoder.setRenderPipelineState(pState)
        encoder.setFragmentTexture(tex, index: 0)
        var region = Self.textureRegion(rect: crop, width: tex.width, height: tex.height)
        encoder.setVertexBytes(&region, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        // Simulator Metal omits presentation callbacks; leave FPS unavailable there.
        #if !targetEnvironment(simulator)
        let presentationGeneration = metrics.measurementGeneration
        let sessionMetrics = metrics
        drawable.addPresentedHandler { displayed in
            sessionMetrics.recordPresentedFrame(at: displayed.presentedTime, generation: presentationGeneration)
        }
        #endif
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Staging buffers live until command completion; the private texture is written only by ordered GPU commands.
    @discardableResult
    func encodeFramebufferUpload(framebuffer: Framebuffer, commandBuffer: MTLCommandBuffer, shouldUpload: Bool = true) -> Int? {
        var target = texture
        var pending: [(buffer: MTLBuffer, region: CGRect, stride: Int)] = []
        var nextRevision: UInt64?
        var failed = false
        framebuffer.withPixelChanges(since: uploadedRevision) { pixels, width, height, changes, revision in
            guard width > 0, height > 0, let base = pixels.baseAddress,
                  pixels.count >= width * height * 4 else { failed = true; return }
            let recreate = target == nil || target?.width != width || target?.height != height || textureFramebuffer !== framebuffer
            if recreate {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
                descriptor.usage = [.shaderRead]
                descriptor.storageMode = .private
                target = device.makeTexture(descriptor: descriptor)
            }
            guard target != nil else { failed = true; return }
            guard recreate || shouldUpload else { return }
            let regions = recreate ? [CGRect(x: 0, y: 0, width: width, height: height)] : changes
            for region in regions {
                let rowBytes = Int(region.width) * 4
                // Conservative alignment supports both Apple and discrete Mac GPUs.
                let stride = (rowBytes + 255) & ~255
                guard let buffer = device.makeBuffer(length: stride * Int(region.height), options: .storageModeShared) else {
                    failed = true; return
                }
                for row in 0..<Int(region.height) {
                    memcpy(buffer.contents().advanced(by: row * stride),
                           base.advanced(by: ((Int(region.minY) + row) * width + Int(region.minX)) * 4), rowBytes)
                }
                pending.append((buffer, region, stride))
            }
            nextRevision = revision
        }
        guard !failed, let target else { return nil }
        guard !pending.isEmpty else { return 0 }
        guard let encoder = commandBuffer.makeBlitCommandEncoder() else { return nil }
        var pixelBytes = 0
        for upload in pending {
            let region = upload.region
            encoder.copy(from: upload.buffer, sourceOffset: 0, sourceBytesPerRow: upload.stride, sourceBytesPerImage: 0,
                         sourceSize: MTLSize(width: Int(region.width), height: Int(region.height), depth: 1),
                         to: target, destinationSlice: 0, destinationLevel: 0,
                         destinationOrigin: MTLOrigin(x: Int(region.minX), y: Int(region.minY), z: 0))
            pixelBytes += Int(region.width * region.height) * 4
        }
        encoder.endEncoding()
        texture = target
        textureFramebuffer = framebuffer
        uploadedRevision = nextRevision
        return pixelBytes
    }
}
