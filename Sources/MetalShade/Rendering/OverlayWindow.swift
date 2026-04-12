import AppKit
import Metal
import QuartzCore

final class OverlayWindow: NSWindow {

    let metalLayer = CAMetalLayer()

    // Start with a 1×1 hidden window; we'll resize once a target is picked
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
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

        setupMetalLayer(size: NSSize(width: 1, height: 1), scale: 1)
    }

    private func setupMetalLayer(size: NSSize, scale: CGFloat) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("No Metal device found")
        }
        metalLayer.device               = device
        metalLayer.pixelFormat          = .bgra8Unorm
        metalLayer.framebufferOnly      = false
        metalLayer.isOpaque             = false
        metalLayer.contentsScale        = scale
        metalLayer.drawableSize         = CGSize(width: size.width * scale, height: size.height * scale)
        metalLayer.displaySyncEnabled   = true
        metalLayer.maximumDrawableCount = 2

        let rootView = NSView(frame: NSRect(origin: .zero, size: size))
        rootView.wantsLayer = true
        rootView.layer = metalLayer
        contentView = rootView
    }

    /// Reposition and resize the overlay to cover `cgFrame` (CG / top-left-origin coordinates).
    /// Pass the NSScreen the window lives on so we can flip the Y axis.
    func matchWindow(cgFrame: CGRect, on screen: NSScreen) {
        // CG has origin at top-left of the main screen.
        // NSWindow uses bottom-left origin relative to the main screen.
        let screenHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let nsOriginY    = screenHeight - cgFrame.origin.y - cgFrame.height
        let nsFrame      = NSRect(x: cgFrame.origin.x, y: nsOriginY,
                                  width: cgFrame.width, height: cgFrame.height)

        setFrame(nsFrame, display: false)

        let scale = screen.backingScaleFactor
        metalLayer.contentsScale = scale
        metalLayer.drawableSize  = CGSize(width: cgFrame.width  * scale,
                                          height: cgFrame.height * scale)
        contentView?.frame = NSRect(origin: .zero, size: nsFrame.size)
        metalLayer.frame   = contentView!.bounds
    }
}
