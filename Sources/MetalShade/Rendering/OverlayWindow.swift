import AppKit
import Metal
import QuartzCore

final class OverlayWindow: NSWindow {

    let metalLayer = CAMetalLayer()

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask:   [.borderless],
            backing:     .buffered,
            defer:       false
        )

        backgroundColor    = .clear
        isOpaque           = false
        hasShadow          = false
        ignoresMouseEvents = true
        level              = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        setupMetalLayer(screen: screen)
    }

    private func setupMetalLayer(screen: NSScreen) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("No Metal device found")
        }

        let scale = screen.backingScaleFactor
        metalLayer.device               = device
        metalLayer.pixelFormat          = .bgra8Unorm
        metalLayer.framebufferOnly      = false
        metalLayer.isOpaque             = false
        metalLayer.contentsScale        = scale
        metalLayer.drawableSize         = CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale)
        metalLayer.displaySyncEnabled   = true
        metalLayer.maximumDrawableCount = 2

        let rootView = NSView(frame: screen.frame)
        rootView.wantsLayer = true
        rootView.layer = metalLayer
        contentView = rootView
    }

    func updateForScreen(_ screen: NSScreen) {
        setFrame(screen.frame, display: false)
        let scale = screen.backingScaleFactor
        metalLayer.contentsScale = scale
        metalLayer.drawableSize  = CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale)
    }
}
