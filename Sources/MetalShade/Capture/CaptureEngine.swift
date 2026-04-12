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
    }

    // MARK: - App enumeration (NSWorkspace — no permission needed)

    struct AppInfo {
        let name:     String
        let pid:      pid_t
        let bundleID: String?
        let icon:     NSImage?
    }

    /// Returns all regular (visible) running apps. No Screen Recording permission required.
    static func runningApps() -> [AppInfo] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map { AppInfo(name: $0.localizedName ?? "Unknown",
                           pid:  $0.processIdentifier,
                           bundleID: $0.bundleIdentifier,
                           icon: $0.icon) }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Find Star Stable in the running app list.
    static func findStarStable() -> AppInfo? {
        let keywords = ["star stable", "starstable", "sso"]
        return runningApps().first { app in
            let n = app.name.lowercased()
            let b = (app.bundleID ?? "").lowercased()
            return keywords.contains(where: { n.contains($0) || b.contains($0) })
        }
    }

    // MARK: - Capture by app PID

    /// Captures everything on the main display that belongs to the given app.
    /// Returns the display frame (overlay should cover the full screen).
    func start(appPID: pid_t) async throws -> CGRect {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        )
        guard let display = content.displays.first else {
            throw NSError(domain: "CaptureEngine", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Дисплей не найден"])
        }
        guard let scApp = content.applications.first(where: { $0.processID == appPID }) else {
            throw NSError(domain: "CaptureEngine", code: 3,
                          userInfo: [NSLocalizedDescriptionKey:
                            "Приложение не найдено в ScreenCaptureKit.\n" +
                            "Убедись что в Системных настройках → Конфиденциальность → " +
                            "Запись экрана разрешено MetalShade, затем перезапусти MetalShade."])
        }

        let filter = SCContentFilter(display: display,
                                     including: [scApp],
                                     exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.pixelFormat          = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.width                = display.width
        config.height               = display.height
        config.capturesAudio        = false
        if #available(macOS 14.0, *) { config.shouldBeOpaque = true }
        config.colorSpaceName       = CGColorSpace.sRGB

        stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream?.addStreamOutput(self, type: .screen,
                                    sampleHandlerQueue: .global(qos: .userInteractive))
        try await stream?.startCapture()

        // Return full display frame in CG coordinates
        return CGRect(x: 0, y: 0, width: display.width, height: display.height)
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
