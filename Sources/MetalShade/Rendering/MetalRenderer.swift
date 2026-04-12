import Metal
import QuartzCore
import CoreVideo

final class MetalRenderer {

    private let device:       MTLDevice
    private let commandQueue: MTLCommandQueue
    private var library:      MTLLibrary?

    private var computePipelines: [String: MTLComputePipelineState] = [:]
    private var displayPipeline:  MTLRenderPipelineState?

    private var pingTexture:     MTLTexture?
    private var pongTexture:     MTLTexture?
    private var lastTextureSize: MTLSize = MTLSize(width: 0, height: 0, depth: 0)

    private weak var overlay: OverlayWindow?
    private var shaderManager: ShaderManager

    init(overlay: OverlayWindow, shaderManager: ShaderManager) {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let queue  = device.makeCommandQueue()
        else { fatalError("Cannot create Metal device or queue") }

        self.device        = device
        self.commandQueue  = queue
        self.overlay       = overlay
        self.shaderManager = shaderManager

        buildLibrary()
        buildDisplayPipeline()
    }

    private func buildLibrary() {
        let options = MTLCompileOptions()
        options.fastMathEnabled = true
        do {
            library = try device.makeLibrary(source: builtinShaderSource, options: options)
        } catch {
            print("Shader compile error: \(error)")
        }
    }

    private func buildComputePipeline(named name: String) -> MTLComputePipelineState? {
        if let cached = computePipelines[name] { return cached }
        guard let lib = library, let fn = lib.makeFunction(name: name) else { return nil }
        do {
            let ps = try device.makeComputePipelineState(function: fn)
            computePipelines[name] = ps
            return ps
        } catch {
            print("Pipeline '\(name)' error: \(error)")
            return nil
        }
    }

    private func buildDisplayPipeline() {
        guard let lib = library else { return }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction   = lib.makeFunction(name: "displayVertex")
        desc.fragmentFunction = lib.makeFunction(name: "displayFragment")
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        desc.colorAttachments[0]!.isBlendingEnabled = false
        do {
            displayPipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            print("Display pipeline error: \(error)")
        }
    }

    func process(pixelBuffer: CVPixelBuffer) {
        guard
            let overlay       = overlay,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let drawable      = overlay.metalLayer.nextDrawable()
        else { return }

        guard
            let ioSurface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue(),
            let inputTex  = makeTexture(from: ioSurface,
                                        width:  CVPixelBufferGetWidth(pixelBuffer),
                                        height: CVPixelBufferGetHeight(pixelBuffer))
        else {
            commandBuffer.commit()
            return
        }

        refreshIntermediateTextures(width: inputTex.width, height: inputTex.height)
        guard let ping = pingTexture, let pong = pongTexture else {
            commandBuffer.commit()
            return
        }

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

            let tgSize  = MTLSize(width: 16, height: 16, depth: 1)
            let tgCount = MTLSize(width: (inputTex.width + 15) / 16, height: (inputTex.height + 15) / 16, depth: 1)
            encoder.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)
            encoder.endEncoding()

            swap(&src, &dst)
            dst = (src === ping) ? pong : ping
        }

        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture     = drawable.texture
        passDesc.colorAttachments[0].loadAction  = .clear
        passDesc.colorAttachments[0].storeAction = .store
        passDesc.colorAttachments[0].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        guard
            let renderEncoder   = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc),
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

    private func makeTexture(from surface: IOSurface, width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        desc.usage       = [.shaderRead]
        desc.storageMode = .shared
        return device.makeTexture(descriptor: desc, iosurface: surface, plane: 0)
    }

    private func refreshIntermediateTextures(width: Int, height: Int) {
        let newSize = MTLSize(width: width, height: height, depth: 1)
        guard newSize.width != lastTextureSize.width || newSize.height != lastTextureSize.height else { return }
        lastTextureSize = newSize

        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        desc.usage       = [.shaderRead, .shaderWrite]
        desc.storageMode = .private

        pingTexture = device.makeTexture(descriptor: desc)
        pongTexture = device.makeTexture(descriptor: desc)
    }
}
