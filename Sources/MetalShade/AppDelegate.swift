import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {

    let shaderManager = ShaderManager()

    private var overlayWindow: OverlayWindow?
    private var controlPanel:  NSPanel?
    private var captureEngine: CaptureEngine?
    private var renderer:      MetalRenderer?
    private var cancellables   = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        guard let screen = NSScreen.main else { return }

        CaptureEngine.requestPermission()
        setupOverlay(screen: screen)
        setupControlPanel(screen: screen)
        wireOverlayVisibility()
        startCapture()
    }

    private func setupOverlay(screen: NSScreen) {
        let window = OverlayWindow(screen: screen)
        renderer   = MetalRenderer(overlay: window, shaderManager: shaderManager)
        overlayWindow = window
        window.orderOut(nil)
    }

    private func setupControlPanel(screen: NSScreen) {
        let panelWidth:  CGFloat = 270
        let panelHeight: CGFloat = 480

        let originY = screen.frame.maxY - panelHeight - 52
        let rect    = NSRect(x: 24, y: originY, width: panelWidth, height: panelHeight)

        let panel = NSPanel(
            contentRect: rect,
            styleMask:   [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )

        panel.titlebarAppearsTransparent  = true
        panel.titleVisibility             = .hidden
        panel.isFloatingPanel             = true
        panel.level                       = .floating
        panel.isMovableByWindowBackground = true
        panel.backgroundColor             = .clear
        panel.isOpaque                    = false
        panel.hasShadow                   = true
        panel.collectionBehavior          = [.canJoinAllSpaces, .fullScreenAuxiliary]

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

    private func startCapture() {
        let engine = CaptureEngine()

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
