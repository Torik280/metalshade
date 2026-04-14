import AppKit
import SwiftUI
import Combine
import ScreenCaptureKit
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let shaderManager = ShaderManager()

    private var overlayWindow: OverlayWindow?
    private var controlPanel:  NSPanel?
    private var captureEngine: CaptureEngine?
    private var renderer:      MetalRenderer?
    private var cancellables   = Set<AnyCancellable>()

    private var currentAppPID: pid_t?

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        CaptureEngine.requestPermission()

        let overlay = OverlayWindow()
        renderer    = MetalRenderer(overlay: overlay, shaderManager: shaderManager)
        overlayWindow = overlay

        setupControlPanel()
        wireCallbacks()

        // Auto-connect to Star Stable if already running
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let ssApp = CaptureEngine.findStarStable() {
                self.selectApp(ssApp)
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

    // MARK: - Callbacks

    private func wireCallbacks() {
        shaderManager.onPickWindow = { [weak self] in self?.showWindowPicker() }
        shaderManager.onLoadShader = { [weak self] in self?.showShaderFilePicker() }
        shaderManager.onLoadPreset = { [weak self] in self?.showPresetLoadPicker() }
        shaderManager.onSavePreset = { [weak self] in self?.showPresetSavePicker() }

        shaderManager.$isEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                enabled ? self.overlayWindow?.orderFront(nil) : self.overlayWindow?.orderOut(nil)
            }
            .store(in: &cancellables)
    }

    // MARK: - App picker (NSWorkspace — no Screen Recording permission needed)

    private func showWindowPicker() {
        let apps = CaptureEngine.runningApps()

        guard !apps.isEmpty else {
            showError("Нет запущенных приложений."); return
        }

        let menu = NSMenu(title: "Выбрать приложение")

        // Star Stable pinned to top
        let sorted = apps.sorted { a, _ in
            a.name.lowercased().contains("star stable") || a.name.lowercased().contains("starstable")
        }

        for app in sorted {
            var label = app.name
            if app.name.lowercased().contains("star stable") || app.name.lowercased().contains("starstable") {
                label = "⭐ " + label
            }
            let item = NSMenuItem(title: label,
                                  action: #selector(appMenuItemSelected(_:)),
                                  keyEquivalent: "")
            item.target            = self
            item.representedObject = app as AnyObject
            menu.addItem(item)
        }

        if let panel = controlPanel {
            let origin = NSPoint(x: panel.frame.minX + 10, y: panel.frame.maxY - 30)
            menu.popUp(positioning: nil, at: origin, in: nil)
        }
    }

    @objc private func appMenuItemSelected(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? CaptureEngine.AppInfo else { return }
        selectApp(app)
    }

    private func selectApp(_ app: CaptureEngine.AppInfo) {
        shaderManager.targetWindowTitle = app.name

        let old = captureEngine
        captureEngine = nil
        Task { await old?.stop() }

        currentAppPID = app.pid

        let engine = CaptureEngine()
        engine.onFrame = { [weak self] pixelBuffer in
            guard let self, self.shaderManager.isEnabled else { return }
            self.renderer?.process(pixelBuffer: pixelBuffer)
        }
        captureEngine = engine

        Task { @MainActor in
            do {
                let frame = try await engine.start(appPID: app.pid)
                guard let screen = NSScreen.main else { return }
                self.overlayWindow?.matchWindow(cgFrame: frame, on: screen)
                if self.shaderManager.isEnabled { self.overlayWindow?.orderFront(nil) }
            } catch {
                let nsError = error as NSError
                // Error code 3 is "app not found in SCK" — not a permission problem
                if nsError.domain == "CaptureEngine" && nsError.code == 3 {
                    self.showAppNotFoundError(app)
                } else {
                    self.showCapturePermissionError(error, retryApp: app)
                }
            }
        }
    }

    // MARK: - Shader file picker

    private func showShaderFilePicker() {
        let panel = NSOpenPanel()
        panel.title                   = "Загрузить шейдер"
        panel.canChooseFiles          = true
        panel.canChooseDirectories    = false
        panel.allowsMultipleSelection = false
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [UTType(filenameExtension: "fx"),
                                         UTType(filenameExtension: "metal")].compactMap { $0 }
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadShader(from: url)
    }

    private func loadShader(from url: URL) {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            showError("Не удалось прочитать файл \(url.lastPathComponent)"); return
        }

        if url.pathExtension.lowercased() == "metal" {
            let fnName      = "fx_" + FXConverter.sanitizeName(url.deletingPathExtension().lastPathComponent)
            let displayName = url.deletingPathExtension().lastPathComponent
            let params      = [ShaderParam(name: "intensity", label: "Intensity", min: 0, max: 1, value: 0.5)]
            if !shaderManager.addCustomShader(name: displayName, functionName: fnName,
                                              source: source, params: params) {
                showError("Ошибка компиляции Metal шейдера.")
            }
        } else {
            let (result, error) = FXConverter.convert(source: source, fileName: url.lastPathComponent)
            if let err = error { showError(err); return }
            guard let res = result else { return }

            let params = res.uniforms.map {
                ShaderParam(name: $0.name, label: $0.label,
                            min: $0.min, max: $0.max, value: $0.defaultValue)
            }
            if !shaderManager.addCustomShader(name: res.displayName, functionName: res.functionName,
                                              source: res.mslSource, params: params) {
                showError("Ошибка компиляции шейдера.\nШейдер может использовать неподдерживаемые HLSL функции.")
            }
        }
    }

    // MARK: - Preset load / save

    private func showPresetLoadPicker() {
        let panel = NSOpenPanel()
        panel.title                   = "Загрузить пресет"
        panel.canChooseFiles          = true
        panel.canChooseDirectories    = false
        panel.allowsMultipleSelection = false
        if #available(macOS 12.0, *) {
            if let ini = UTType(filenameExtension: "ini") { panel.allowedContentTypes = [ini] }
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let (preset, error) = PresetManager.load(from: url)
        if let err = error { showError(err); return }
        guard let preset else { return }

        // First pass: apply to built-in/already-loaded effects
        var result = shaderManager.applyPreset(preset)

        // Auto-load unmatched .fx files from the same folder as the INI
        if !result.unmatchedFiles.isEmpty {
            let iniDir   = url.deletingLastPathComponent()
            let loaded   = autoLoadShaders(fileNames: result.unmatchedFiles, from: iniDir)

            if !loaded.isEmpty {
                // Second pass: now that custom shaders are loaded, re-apply the preset
                result = shaderManager.applyPreset(preset)
            }
        }

        shaderManager.lastPresetName   = url.deletingPathExtension().lastPathComponent
        shaderManager.lastPresetStatus = result.summary
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
            self.shaderManager.lastPresetStatus = nil
        }
    }

    /// Scans `directory` for the given .fx / .metal filenames and silently loads
    /// the ones found. Already-loaded shaders with the same name are skipped.
    /// Returns the display names of successfully loaded shaders.
    @discardableResult
    private func autoLoadShaders(fileNames: [String], from directory: URL) -> [String] {
        var loaded: [String] = []
        let fm = FileManager.default

        for fileName in fileNames {
            let fileURL = directory.appendingPathComponent(fileName)
            guard fm.fileExists(atPath: fileURL.path),
                  let source = try? String(contentsOf: fileURL, encoding: .utf8)
            else { continue }

            let ext = fileURL.pathExtension.lowercased()
            let baseName = fileURL.deletingPathExtension().lastPathComponent

            // Skip if an effect with this name is already loaded
            if shaderManager.effects.contains(where: {
                $0.name.lowercased() == baseName.lowercased()
            }) { continue }

            if ext == "metal" {
                let fnName = "fx_" + FXConverter.sanitizeName(baseName)
                let params = [ShaderParam(name: "intensity", label: "Intensity",
                                         min: 0, max: 1, value: 0.5)]
                if shaderManager.addCustomShader(name: baseName, functionName: fnName,
                                                 source: source, params: params) {
                    loaded.append(baseName)
                }
            } else if ext == "fx" {
                let (res, _) = FXConverter.convert(source: source, fileName: fileName)
                guard let res else { continue }
                let params = res.uniforms.map {
                    ShaderParam(name: $0.name, label: $0.label,
                                min: $0.min, max: $0.max, value: $0.defaultValue)
                }
                if shaderManager.addCustomShader(name: res.displayName, functionName: res.functionName,
                                                 source: res.mslSource, params: params) {
                    loaded.append(res.displayName)
                }
            }
        }
        return loaded
    }

    private func showPresetSavePicker() {
        let panel = NSSavePanel()
        panel.title               = "Сохранить пресет"
        panel.nameFieldStringValue = "MetalShadePreset.ini"
        if #available(macOS 12.0, *) {
            if let ini = UTType(filenameExtension: "ini") { panel.allowedContentTypes = [ini] }
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let err = PresetManager.save(effects: shaderManager.effects, to: url) { showError(err) }
    }

    private func showCapturePermissionError(_ error: Error, retryApp: CaptureEngine.AppInfo? = nil) {
        let alert = NSAlert()
        alert.messageText = "Нет доступа к захвату экрана"
        alert.informativeText = """
            MetalShade нужно разрешение на Запись экрана.

            1. Нажми «Открыть настройки» ниже
            2. Найди MetalShade → включи переключатель
               (если уже включён — выключи и включи снова)
            3. Вернись в MetalShade и нажми «Повторить»

            Ошибка: \(error.localizedDescription)
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Открыть настройки")
        if retryApp != nil { alert.addButton(withTitle: "Повторить") }
        alert.addButton(withTitle: "Закрыть")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            )
        } else if let app = retryApp, response.rawValue == 1001 {
            // "Повторить" — retry after user granted permission
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.selectApp(app)
            }
        }
    }

    private func showAppNotFoundError(_ app: CaptureEngine.AppInfo) {
        let alert = NSAlert()
        alert.messageText = "Приложение не найдено"
        alert.informativeText = """
            «\(app.name)» запущено, но ScreenCaptureKit его не видит.

            Возможные причины:
            • У приложения нет видимых окон — открой игру в оконном режиме
            • Приложение запущено под другим пользователем
            • Нет разрешения на Запись экрана

            Попробуй выбрать приложение ещё раз после того, как оно откроет окно.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Открыть настройки записи")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            )
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText     = "Ошибка"
        alert.informativeText = message
        alert.alertStyle      = .warning
        alert.runModal()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
