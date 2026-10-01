import Foundation
import Metal
import MetalKit

/// High-performance Metal renderer for remote desktop framebuffers.
/// Capable of rendering at up to 120 FPS on ProMotion displays (iOS & Apple Silicon Mac).
public final class MetalScreenRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {

    public let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var texture: MTLTexture?
    private weak var attachedView: MTKView?

    public weak var framebuffer: Framebuffer?
    public let metrics: PerformanceMetrics

    private let lock = NSLock()
    private var needsTextureRecreation: Bool = true
    private var isDirty: Bool = true
    private var displayScheduled = false

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
    };

    vertex VertexOut screenVertex(uint vid [[vertex_id]]) {
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
        out.texCoord = texCoords[vid];
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

    public func draw(in view: MTKView) {
        guard let pState = pipelineState,
              let fb = framebuffer,
              let currentDrawable = view.currentDrawable,
              let renderPassDesc = view.currentRenderPassDescriptor else {
            return
        }

        lock.lock()
        let dirty = isDirty
        isDirty = false
        lock.unlock()

        // Synchronize and update texture if framebuffer size changed or dirty
        updateTextureIfNeeded(framebuffer: fb, shouldUpload: dirty)

        guard let tex = self.texture else { return }

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else {
            return
        }

        renderEncoder.setRenderPipelineState(pState)
        renderEncoder.setFragmentTexture(tex, index: 0)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()

        commandBuffer.present(currentDrawable)
        commandBuffer.commit()

        metrics.recordFrame()
    }

    private func updateTextureIfNeeded(framebuffer: Framebuffer, shouldUpload: Bool) {
        framebuffer.withPixelBytes { pixels, width, height in
            guard width > 0, height > 0 else { return }

            if texture == nil || texture?.width != width || texture?.height != height {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm,
                    width: width,
                    height: height,
                    mipmapped: false
                )
                descriptor.usage = [.shaderRead]
                #if os(macOS)
                descriptor.storageMode = .managed
                #else
                descriptor.storageMode = .shared
                #endif
                texture = device.makeTexture(descriptor: descriptor)
            }

            guard shouldUpload,
                  let tex = texture,
                  let base = pixels.baseAddress,
                  pixels.count >= width * height * 4 else { return }
            tex.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: base,
                bytesPerRow: width * 4
            )
        }
    }
}
