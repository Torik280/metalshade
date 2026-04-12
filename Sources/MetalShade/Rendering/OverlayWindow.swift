import AppKit
import Metal
import QuartzCore

// MARK: - Transparent, click-through, fullscreen overlay window
//
// Sits above all other windows. Renders the post-processed frame via CAMetalLayer.
// ignoresMouseEvents = true → all mouse/keyboard events pass through to the game.

final class OverlayWindow: NSWindow {

    let metalLayer = CAMetalLayer()

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask:   [.borderless],
            backing:     .buffered,
            defer:       false,
            screen:      screen
        )

        // Transparent background — only the Metal layer is visible
        backgroundColor       = .clear
        isOpaque              = false
        hasShadow             = false
        ignoresMouseEvents    = true
        level                 = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) - 1)
        collectionBehavior    = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        setupMetalLayer(screen: screen)
    }

    private func setupMetalLayer(screen: NSScreen) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("MetalShade: No Metal device found")
        }

        let scale = screen.backingScaleFactor
        metalLayer.device           = device
        metalLayer.pixelFormat      = .bgra8Unorm
        metalLayer.framebufferOnly  = false                 // allow blit reads if needed
        metalLayer.isOpaque         = false
        metalLayer.contentsScale    = scale
        metalLayer.drawableSize     = CGSize(
            width:  screen.frame.width  * scale,
            height: screen.frame.height * scale
        )
        // Present as soon as the GPU finishes — lowest latency
        metalLayer.displaySyncEnabled = true
        metalLayer.maximumDrawableCount = 2

        let rootView = NSView(frame: screen.frame)
        rootView.wantsLayer = true
        rootView.layer = metalLayer
        contentView = rootView
    }

    // Keep overlay in sync when display resolution changes
    func updateForScreen(_ screen: NSScreen) {
        setFrame(screen.frame, display: false)
        let scale = screen.backingScaleFactor
        metalLayer.contentsScale = scale
        metalLayer.drawableSize  = CGSize(
            width:  screen.frame.width  * scale,
            height: screen.frame.height * scale
        )
    }
}
