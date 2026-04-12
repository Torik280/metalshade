import ScreenCaptureKit
import CoreMedia
import CoreVideo
import AppKit

final class CaptureEngine: NSObject {

    private var stream: SCStream?
    var onFrame: ((CVPixelBuffer) -> Void)?

    static func requestPermission() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    // Returns all windows with titles (for the picker)
    static func availableWindows() async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        )
        return content.windows.filter {
            guard let title = $0.title else { return false }
            return !title.isEmpty
        }
    }

    // Find Star Stable window specifically
    static func findStarStable() async -> SCWindow? {
        guard let windows = try? await availableWindows() else { return nil }
        let ssKeywords = ["star stable", "starstable", "sso"]
        return windows.first { w in
            let appName = (w.owningApplication?.applicationName ?? "").lowercased()
            let title   = (w.title ?? "").lowercased()
            return ssKeywords.contains(where: { appName.contains($0) || title.contains($0) })
        }
    }

    // Capture a specific window. Returns its frame in screen coordinates (CG, top-left origin).
    func start(windowID: CGWindowID) async throws -> CGRect {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw NSError(domain: "CaptureEngine", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Window \(windowID) not found"])
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)

        let config = SCStreamConfiguration()
        config.pixelFormat          = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.width                = Int(window.frame.width)
        config.height               = Int(window.frame.height)
        config.capturesAudio        = false
        if #available(macOS 14.0, *) { config.shouldBeOpaque = true }
        config.colorSpaceName       = CGColorSpace.sRGB

        stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream?.addStreamOutput(self, type: .screen,
                                    sampleHandlerQueue: .global(qos: .userInteractive))
        try await stream?.startCapture()

        return window.frame
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }
}

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
