import ScreenCaptureKit
import CoreMedia
import CoreVideo
import AppKit

final class CaptureEngine: NSObject {

    private var stream: SCStream?
    var onFrame: ((CVPixelBuffer) -> Void)?

    // MARK: - Permission

    static func requestPermission() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
        Task {
            _ = try? await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false
            )
        }
    }

    // MARK: - App enumeration

    struct AppInfo {
        let name:     String
        let pid:      pid_t
        let bundleID: String?
        let icon:     NSImage?
    }

    static func runningApps() -> [AppInfo] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map { AppInfo(name: $0.localizedName ?? "Unknown",
                           pid:  $0.processIdentifier,
                           bundleID: $0.bundleIdentifier,
                           icon: $0.icon) }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    static func findStarStable() -> AppInfo? {
        let keywords = ["star stable", "starstable", "sso"]
        return runningApps().first { app in
            let n = app.name.lowercased()
            let b = (app.bundleID ?? "").lowercased()
            return keywords.contains(where: { n.contains($0) || b.contains($0) })
        }
    }

    // MARK: - Capture session

    struct CaptureSession {
        /// Window frame in CG-point coordinates (top-left origin).
        /// The overlay is sized and positioned to exactly this rect.
        let overlayFrame: CGRect
    }

    // MARK: - Start

    /// Finds the main window of the target app and captures it independently.
    /// Uses SCContentFilter(desktopIndependentWindow:) so the captured texture
    /// is exactly the window — no extra screen area, no transparency issues.
    func start(appPID: pid_t) async throws -> CaptureSession {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )

        guard content.applications.contains(where: { $0.processID == appPID }) else {
            throw NSError(domain: "CaptureEngine", code: 3,
                          userInfo: [NSLocalizedDescriptionKey:
                            "Приложение не найдено в ScreenCaptureKit.\n" +
                            "Убедись что в Системных настройках → Конфиденциальность → " +
                            "Запись экрана разрешено MetalShade, затем перезапусти MetalShade."])
        }

        // Find the main (largest visible) window of the target app
        let appWindows = content.windows.filter {
            $0.owningApplication?.processID == appPID &&
            $0.isOnScreen &&
            $0.windowLayer == 0 &&
            $0.frame.width > 50 && $0.frame.height > 50
        }
        guard let mainWindow = appWindows.max(by: {
            $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
        }) else {
            throw NSError(domain: "CaptureEngine", code: 4,
                          userInfo: [NSLocalizedDescriptionKey:
                            "У приложения нет видимых окон.\n" +
                            "Открой приложение в оконном режиме и попробуй снова."])
        }

        // Capture this specific window — texture = exactly the window, no other content
        let filter = SCContentFilter(desktopIndependentWindow: mainWindow)

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let config = SCStreamConfiguration()
        config.pixelFormat          = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.width                = Int(mainWindow.frame.width  * scale)
        config.height               = Int(mainWindow.frame.height * scale)
        config.capturesAudio        = false
        config.colorSpaceName       = CGColorSpace.sRGB

        stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream?.addStreamOutput(self, type: .screen,
                                    sampleHandlerQueue: .global(qos: .userInteractive))
        try await stream?.startCapture()

        // mainWindow.frame is in CG-point coordinates (top-left origin) — pass directly
        return CaptureSession(overlayFrame: mainWindow.frame)
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }
}

// MARK: - SCStreamOutput / Delegate

extension CaptureEngine: SCStreamOutput {
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen,
              CMSampleBufferIsValid(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }
        onFrame?(pixelBuffer)
    }
}

extension CaptureEngine: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("CaptureEngine stopped: \(error.localizedDescription)")
    }
}
