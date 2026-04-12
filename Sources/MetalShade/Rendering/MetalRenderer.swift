import Metal
import QuartzCore
import CoreVideo

// MARK: - MetalRenderer
//
// Owns the GPU pipeline.  For each captured frame:
//   1. Import the IOSurface-backed CVPixelBuffer as a MTLTexture (zero-copy).
//   2. Run enabled compute shaders in order using ping-pong textures.
//   3. Draw the result to the OverlayWindow's CAMetalLayer via a render pass.

final class MetalRenderer {

    // ── Metal objects ──────────────────────────────────────────────────────

    private let device:       MTLDevice
    private let commandQueue: MTLCommandQueue
    private var library:      MTLLibrary?

    /// Compiled compute pipeline states, keyed by shader function name.
    private var computePipelines: [String: MTLComputePipelineState] = [:]

    /// Single render pipeline for drawing the processed texture to the drawable.
    private var displayPipeline: MTLRenderPipelineState?

    // ── Ping-pong intermediate textures ───────────────────────────────────

    private var pingTexture: MTLTexture?
    private var pongTexture: MTLTexture?
    private var lastTextureSize: MTLSize = MTLSize(width: 0, height: 0, depth: 0)

    // ── External references ────────────────────────────────────────────────

    private weak var overlay: OverlayWindow?
    private var shaderManager: ShaderManager

    // ── Init ───────────────────────────────────────────────────────────────

    init(overlay: OverlayWindow, shaderManager: ShaderManager) {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let queue  = device.makeCommandQueue()
        else { fatalError("MetalShade: cannot create Metal device or queue") }

        self.device        = device
        self.commandQueue  = queue
        self.overlay       = overlay
        self.shaderManager = shaderManager

        buildLibrary()
        buildDisplayPipeline()
    }

    // MARK: - Library / pipeline setup

    private func buildLibrary() {
        let options = MTLCompileOptions()
        options.fastMathEnabled = true

        do {
            library = try device.makeLibrary(source: builtinShaderSource, options: options)
        } catch {
            print("MetalShade: shader compile error — \(error)")
        }
    }

    /// Pre-build compute pipeline states for all known shaders.
    private func buildComputePipeline(named functionName: String) -> MTLComputePipelineState? {
        if let cached = computePipelines[functionName] { return cached }
        guard
            let lib  = library,
            let fn   = lib.makeFunction(name: functionName)
        else { return nil }

        do {
            let ps = try device.makeComputePipelineState(function: fn)
            computePipelines[functionName] = ps
            return ps
        } catch {
            print("MetalShade: cannot build pipeline '\(functionName)' — \(error)")
            return nil
        }
    }

    private func buildDisplayPipeline() {
        guard let lib = library else { return }
        let desc                   = MTLRenderPipelineDescriptor()
        desc.vertexFunction        = lib.makeFunction(name: "displayVertex")
        desc.fragmentFunction      = lib.makeFunction(name: "displayFragment")
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        // Straight-alpha blend: overlay replaces what's underneath
        let att = desc.colorAttachments[0]!
        att.isBlendingEnabled = false

        do {
            displayPipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            print("MetalShade: display pipeline error — \(error)")
        }
    }

    // MARK: - Per-frame processing (called from CaptureEngine's background queue)

    func process(pixelBuffer: CVPixelBuffer) {
        guard
            let overlay        = overlay,
            let commandBuffer  = commandQueue.makeCommandBuffer(),
            let drawable       = overlay.metalLayer.nextDrawable()
        else { return }

        // ── 1. Wrap the IOSurface in a MTLTexture — zero CPU copy ──────────
        guard
            let ioSurface  = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue(),
            let inputTex   = makeTexture(from: ioSurface,
                                         width:  CVPixelBufferGetWidth(pixelBuffer),
                                         height: CVPixelBufferGetHeight(pixelBuffer))
        else {
            commandBuffer.commit()
            return
        }

        // ── 2. Prepare ping-pong textures ──────────────────────────────────
        refreshIntermediateTextures(width: inputTex.width, height: inputTex.height)
        guard let ping = pingTexture, let pong = pongTexture else {
            commandBuffer.commit()
            return
        }

        // ── 3. Run compute shader chain ────────────────────────────────────
        let activeEffects = shaderManager.activeEffects
        var src: MTLTexture = inputTex
        var dst: MTLTexture = ping

        for effect in activeEffects {
            guard let pipeline = buildComputePipeline(named: effect.functionName) else { continue }

            let encoder = commandBuffer.makeComputeCommandEncoder()!
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(src, index: 0)
            encoder.setTexture(dst, index: 1)
            var intensity = effect.intensity
            encoder.setBytes(&intensity, length: MemoryLayout<Float>.size, index: 0)

            // Thread group sizing: 16×16 is optimal for most Apple Silicon GPUs
            let tgSize = MTLSize(width: 16, height: 16, depth: 1)
            let tgCount = MTLSize(
                width:  (inputTex.width  + 15) / 16,
                height: (inputTex.height + 15) / 16,
                depth:  1
            )
            encoder.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)
            encoder.endEncoding()

            swap(&src, &dst)
            dst = (src === ping) ? pong : ping
        }

        // `src` now holds the final processed frame (or the raw input if no effects ran)

        // ── 4. Draw to CAMetalLayer drawable via render pass ───────────────
        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture     = drawable.texture
        passDesc.colorAttachments[0].loadAction  = .clear
        passDesc.colorAttachments[0].storeAction = .store
        passDesc.colorAttachments[0].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        guard
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc),
            let displayPipeline = displayPipeline
        else {
            commandBuffer.commit()
            return
        }

        renderEncoder.setRenderPipelineState(displayPipeline)
        renderEncoder.setFragmentTexture(src, index: 0)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        renderEncoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Helpers

    private func makeTexture(from surface: IOSurface, width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width:       width,
            height:      height,
            mipmapped:   false
        )
        desc.usage        = [.shaderRead]
        desc.storageMode  = .shared    // IOSurface lives in shared GPU/CPU memory
        return device.makeTexture(descriptor: desc, iosurface: surface, plane: 0)
    }

    private func refreshIntermediateTextures(width: Int, height: Int) {
        let newSize = MTLSize(width: width, height: height, depth: 1)
        guard newSize.width  != lastTextureSize.width ||
              newSize.height != lastTextureSize.height
        else { return }

        lastTextureSize = newSize

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width:       width,
            height:      height,
            mipmapped:   false
        )
        desc.usage       = [.shaderRead, .shaderWrite]
        desc.storageMode = .private     // GPU-only, fastest

        pingTexture = device.makeTexture(descriptor: desc)
        pongTexture = device.makeTexture(descriptor: desc)
    }
}
