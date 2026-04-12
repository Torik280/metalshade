import AppKit
import SwiftUI
import Combine
import ScreenCaptureKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {

    let shaderManager = ShaderManager()

    private var overlayWindow: OverlayWindow?
    private var controlPanel:  NSPanel?
    private var captureEngine: CaptureEngine?
    private var renderer:      MetalRenderer?
    private var cancellables   = Set<AnyCancellable>()

    private var trackingTimer:   Timer?
    private var currentWindowID: CGWindowID?

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        CaptureEngine.requestPermission()

        let overlay = OverlayWindow()
        renderer    = MetalRenderer(overlay: overlay, shaderManager: shaderManager)
        overlayWindow = overlay

        setupControlPanel()
        wireCallbacks()

        // Try to auto-connect to Star Stable if it's already running
        Task {
            if let ssWindow = await CaptureEngine.findStarStable() {
                await MainActor.run { self.selectWindow(ssWindow) }
            }
        }
    }

    // MARK: - Control panel

    private func setupControlPanel() {
        guard let screen = NSScreen.main else { return }

        let panelWidth:  CGFloat = 270
        let panelHeight: CGFloat = 520

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

        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .forEach { panel.standardWindowButton($0)?.isHidden = true }

        panel.contentView = NSHostingView(
            rootView: ControlPanel(manager: shaderManager)
                .frame(width: panelWidth, height: panelHeight)
                .ignoresSafeArea()
        )
        panel.makeKeyAndOrderFront(nil)
        controlPanel = panel
    }

    // MARK: - Callbacks wired to ShaderManager

    private func wireCallbacks() {
        shaderManager.onPickWindow = { [weak self] in
            self?.showWindowPicker()
        }
        shaderManager.onLoadShader = { [weak self] in
            self?.showShaderFilePicker()
        }
        shaderManager.onLoadPreset = { [weak self] in
            self?.showPresetLoadPicker()
        }
        shaderManager.onSavePreset = { [weak self] in
            self?.showPresetSavePicker()
        }

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

    // MARK: - Window picker

    private func showWindowPicker() {
        Task { @MainActor in
            let windows: [SCWindow]
            do {
                windows = try await CaptureEngine.availableWindows()
            } catch {
                let alert = NSAlert()
                alert.messageText     = "Нет доступа к списку окон"
                alert.informativeText = "Открой Системные настройки → Конфиденциальность и безопасность → Запись экрана и разреши MetalShade.\n\nОшибка: \(error.localizedDescription)"
                alert.alertStyle      = .warning
                alert.addButton(withTitle: "Открыть настройки")
                alert.addButton(withTitle: "Закрыть")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }
                return
            }

            guard !windows.isEmpty else {
                let alert = NSAlert()
                alert.messageText     = "Нет доступных окон"
                alert.informativeText = "Запусти Star Stable Online и нажми «Выбрать» снова."
                alert.runModal()
                return
            }

            let menu = NSMenu(title: "Выбрать окно")

            // Pin Star Stable to the top if present
            let sorted = windows.sorted { a, _ in
                let n = (a.owningApplication?.applicationName ?? "").lowercased()
                return n.contains("star stable") || n.contains("starstable")
            }

            for window in sorted {
                let title   = window.title ?? "Без названия"
                let appName = window.owningApplication?.applicationName ?? ""
                var label   = appName.isEmpty ? title : "\(appName) — \(title)"
                if appName.lowercased().contains("star stable") || appName.lowercased().contains("starstable") {
                    label = "⭐ " + label
                }
                let item           = NSMenuItem(title: label,
                                                action: #selector(self.windowMenuItemSelected(_:)),
                                                keyEquivalent: "")
                item.target            = self
                item.representedObject = window
                menu.addItem(item)
            }

            if let panel = controlPanel {
                let origin = NSPoint(x: panel.frame.minX + 10, y: panel.frame.maxY - 30)
                menu.popUp(positioning: nil, at: origin, in: nil)
            }
        }
    }

    @objc private func windowMenuItemSelected(_ sender: NSMenuItem) {
        guard let window = sender.representedObject as? SCWindow else { return }
        selectWindow(window)
    }

    private func selectWindow(_ scWindow: SCWindow) {
        let windowID = scWindow.windowID
        let appName  = scWindow.owningApplication?.applicationName ?? ""
        let title    = scWindow.title ?? "Окно"
        let label    = appName.isEmpty ? title : "\(appName) — \(title)"

        DispatchQueue.main.async {
            self.shaderManager.targetWindowTitle = label
        }

        // Stop previous capture
        trackingTimer?.invalidate()
        trackingTimer = nil
        let oldEngine = captureEngine
        captureEngine = nil
        Task { await oldEngine?.stop() }

        currentWindowID = windowID

        // Start new window-specific capture
        let engine = CaptureEngine()
        engine.onFrame = { [weak self] pixelBuffer in
            guard let self, self.shaderManager.isEnabled else { return }
            self.renderer?.process(pixelBuffer: pixelBuffer)
        }
        captureEngine = engine

        Task { @MainActor in
            do {
                let frame = try await engine.start(windowID: windowID)
                guard let screen = NSScreen.main else { return }
                self.overlayWindow?.matchWindow(cgFrame: frame, on: screen)
                if self.shaderManager.isEnabled {
                    self.overlayWindow?.orderFront(nil)
                }
                // Poll window position every 150ms to follow window movement
                self.trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
                    self?.updateOverlayPosition()
                }
            } catch {
                print("Capture error: \(error)")
            }
        }
    }

    private func updateOverlayPosition() {
        guard let windowID = currentWindowID, let screen = NSScreen.main else { return }
        Task {
            let windows = await CaptureEngine.availableWindows()
            guard let win = windows.first(where: { $0.windowID == windowID }) else { return }
            await MainActor.run {
                self.overlayWindow?.matchWindow(cgFrame: win.frame, on: screen)
            }
        }
    }

    // MARK: - Shader file picker

    private func showShaderFilePicker() {
        let panel = NSOpenPanel()
        panel.title               = "Загрузить шейдер"
        panel.canChooseFiles      = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        // Allow .fx and .metal files
        if #available(macOS 12.0, *) {
            let fx    = UTType(filenameExtension: "fx")
            let metal = UTType(filenameExtension: "metal")
            panel.allowedContentTypes = [fx, metal].compactMap { $0 }
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadShader(from: url)
    }

    private func loadShader(from url: URL) {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            showError("Не удалось прочитать файл \(url.lastPathComponent)")
            return
        }

        let ext = url.pathExtension.lowercased()

        if ext == "metal" {
            // Load as-is — user wrote it in MSL
            // Expect a function named fx_<filename>
            let fnName = "fx_" + FXConverter.sanitizeName(url.deletingPathExtension().lastPathComponent)
            let displayName = url.deletingPathExtension().lastPathComponent
            let params  = [ShaderParam(name: "intensity", label: "Intensity", min: 0, max: 1, value: 0.5)]
            if !shaderManager.addCustomShader(name: displayName, functionName: fnName,
                                              source: source, params: params) {
                showError("Ошибка компиляции Metal шейдера.\nПроверь консоль для деталей.")
            }
        } else {
            // .fx — convert via FXConverter
            let (result, error) = FXConverter.convert(source: source,
                                                       fileName: url.lastPathComponent)
            if let err = error {
                showError(err)
                return
            }
            guard let res = result else { return }

            // Build ShaderParam list from parsed uniforms
            let params: [ShaderParam] = res.uniforms.map {
                ShaderParam(name: $0.name, label: $0.label,
                            min: $0.min, max: $0.max, value: $0.defaultValue)
            }

            if !shaderManager.addCustomShader(name: res.displayName,
                                               functionName: res.functionName,
                                               source: res.mslSource,
                                               params: params) {
                showError("Ошибка компиляции конвертированного шейдера.\n" +
                          "Шейдер может использовать неподдерживаемые HLSL функции.")
            }
        }
    }

    // MARK: - Preset load / save

    private func showPresetLoadPicker() {
        let panel = NSOpenPanel()
        panel.title               = "Загрузить пресет"
        panel.canChooseFiles      = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if #available(macOS 12.0, *) {
            if let ini = UTType(filenameExtension: "ini") {
                panel.allowedContentTypes = [ini]
            }
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let (preset, error) = PresetManager.load(from: url)
        if let err = error { showError(err); return }
        guard let preset else { return }

        DispatchQueue.main.async {
            let summary = self.shaderManager.applyPreset(preset)
            self.shaderManager.lastPresetName   = url.deletingPathExtension().lastPathComponent
            self.shaderManager.lastPresetStatus = summary

            // Brief success flash then clear after 4 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                self.shaderManager.lastPresetStatus = nil
            }
        }
    }

    private func showPresetSavePicker() {
        let panel = NSSavePanel()
        panel.title              = "Сохранить пресет"
        panel.nameFieldStringValue = "MetalShadePreset.ini"
        if #available(macOS 12.0, *) {
            if let ini = UTType(filenameExtension: "ini") {
                panel.allowedContentTypes = [ini]
            }
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        if let err = PresetManager.save(effects: shaderManager.effects, to: url) {
            showError(err)
        }
    }

    private func showError(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText     = "Ошибка загрузки шейдера"
            alert.informativeText = message
            alert.alertStyle      = .warning
            alert.runModal()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
