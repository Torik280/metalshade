import AppKit
import SwiftUI
import Combine

// MARK: - AppDelegate
//
// Boot order:
//   1. Transparent fullscreen overlay window (click-through, above all apps).
//   2. Floating neon control panel (non-activating, can't steal focus from the game).
//   3. Both windows excluded from screen capture → no feedback loop.
//   4. CaptureEngine delivers frames → MetalRenderer processes & displays them.
//   5. ShaderManager.isEnabled drives overlay visibility.

final class AppDelegate: NSObject, NSApplicationDelegate {

    let shaderManager = ShaderManager()

    private var overlayWindow: OverlayWindow?
    private var controlPanel:  NSPanel?
    private var captureEngine: CaptureEngine?
    private var renderer:      MetalRenderer?
    private var cancellables   = Set<AnyCancellable>()

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // no Dock icon

        guard let screen = NSScreen.main else { return }

        CaptureEngine.requestPermission()
        setupOverlay(screen: screen)
        setupControlPanel(screen: screen)
        wireOverlayVisibility()
        startCapture()
    }

    // MARK: - Overlay

    private func setupOverlay(screen: NSScreen) {
        let window = OverlayWindow(screen: screen)
        renderer   = MetalRenderer(overlay: window, shaderManager: shaderManager)
        overlayWindow = window
        window.orderOut(nil)   // hidden until the user enables post-processing
    }

    // MARK: - Control panel

    private func setupControlPanel(screen: NSScreen) {
        let panelWidth:  CGFloat = 270
        let panelHeight: CGFloat = 480

        // Position near top-left, clear of the menu bar (28 pt)
        let originY = screen.frame.maxY - panelHeight - 52
        let rect    = NSRect(x: 24, y: originY, width: panelWidth, height: panelHeight)

        let panel = NSPanel(
            contentRect: rect,
            styleMask:   [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )

        // Transparent title bar so our SwiftUI skin takes over completely
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility            = .hidden
        panel.isFloatingPanel            = true
        panel.level                      = .floating
        panel.isMovableByWindowBackground = true
        panel.backgroundColor            = .clear
        panel.isOpaque                   = false
        panel.hasShadow                  = true
        panel.collectionBehavior         = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Hide traffic lights — our SwiftUI panel has its own close button
        [NSWindow.ButtonType.closeButton,
         .miniaturizeButton,
         .zoomButton].forEach { panel.standardWindowButton($0)?.isHidden = true }

        panel.contentView = NSHostingView(
            rootView: ControlPanel(manager: shaderManager)
                .frame(width: panelWidth, height: panelHeight)
                .ignoresSafeArea()
        )

        panel.makeKeyAndOrderFront(nil)
        controlPanel = panel
    }

    // MARK: - Overlay visibility

    private func wireOverlayVisibility() {
        shaderManager.$isEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.overlayWindow?.orderFront(nil)
                } else {
                    self.overlayWindow?.orderOut(nil)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Capture

    private func startCapture() {
        let engine = CaptureEngine()

        // Collect window IDs to exclude after the windows are on screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self, weak engine] in
            guard let self, let engine else { return }
            var ids = Set<CGWindowID>()
            if let n = self.overlayWindow?.windowNumber, n > 0 { ids.insert(CGWindowID(n)) }
            if let n = self.controlPanel?.windowNumber,  n > 0 { ids.insert(CGWindowID(n)) }
            engine.excludedWindowIDs = ids
        }

        engine.onFrame = { [weak self] pixelBuffer in
            guard let self, self.shaderManager.isEnabled else { return }
            self.renderer?.process(pixelBuffer: pixelBuffer)
        }

        captureEngine = engine
        Task { await engine.start() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
