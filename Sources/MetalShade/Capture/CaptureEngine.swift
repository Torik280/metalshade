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

    // MARK: - Window enumeration (CGWindowList — reliable across all macOS versions)

    struct WindowInfo {
        let windowID: CGWindowID
        let title:    String
        let appName:  String
        let pid:      pid_t
        let frame:    CGRect
    }

    static func availableWindows() -> [WindowInfo] {
        let opts: CGWindowListOption = [.excludeDesktopElements, .optionOnScreenOnly]
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]]
        else { return [] }

        return list.compactMap { info -> WindowInfo? in
            guard
                let wid    = info[kCGWindowNumber      as String] as? CGWindowID,
                let title  = info[kCGWindowName        as String] as? String, !title.isEmpty,
                let app    = info[kCGWindowOwnerName   as String] as? String,
                let pid    = info[kCGWindowOwnerPID    as String] as? pid_t,
                let bounds = info[kCGWindowBounds      as String]
            else { return nil }

            let rect = CGRect(dictionaryRepresentation: bounds as! CFDictionary)
            // Skip tiny system UI elements
            guard rect.width > 100 && rect.height > 100 else { return nil }

            return WindowInfo(windowID: wid, title: title, appName: app, pid: pid, frame: rect)
        }
    }

    // Find Star Stable in the window list
    static func findStarStable() -> WindowInfo? {
        let keywords = ["star stable", "starstable", "sso"]
        return availableWindows().first { w in
            let n = w.appName.lowercased()
            let t = w.title.lowercased()
            return keywords.contains(where: { n.contains($0) || t.contains($0) })
        }
    }

    // MARK: - Start capture for a specific window

    /// Starts capturing `windowInfo.windowID`. Returns the window frame (CG coords).
    func start(windowInfo: WindowInfo) async throws -> CGRect {
        // Try to get the SCWindow by ID; fall back to display-level capture
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        )

        let filter: SCContentFilter
        let captureWidth:  Int
        let captureHeight: Int

        if let scWin = content.windows.first(where: { $0.windowID == windowInfo.windowID }) {
            // Best path: capture only the target window
            filter        = SCContentFilter(desktopIndependentWindow: scWin)
            captureWidth  = Int(windowInfo.frame.width)
            captureHeight = Int(windowInfo.frame.height)
        } else if let display = content.displays.first,
                  let scApp = content.applications.first(where: { $0.processID == windowInfo.pid }) {
            // Fallback: capture the app's portion of the display
            filter        = SCContentFilter(display: display,
                                            including: [scApp],
                                            exceptingWindows: [])
            captureWidth  = Int(windowInfo.frame.width)
            captureHeight = Int(windowInfo.frame.height)
        } else {
            throw NSError(domain: "CaptureEngine", code: 1,
                          userInfo: [NSLocalizedDescriptionKey:
                            "Не удалось найти окно в ScreenCaptureKit. " +
                            "Попробуй перезапустить игру и MetalShade."])
        }

        let config = SCStreamConfiguration()
        config.pixelFormat          = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.width                = captureWidth
        config.height               = captureHeight
        config.capturesAudio        = false
        if #available(macOS 14.0, *) { config.shouldBeOpaque = true }
        config.colorSpaceName       = CGColorSpace.sRGB

        stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream?.addStreamOutput(self, type: .screen,
                                    sampleHandlerQueue: .global(qos: .userInteractive))
        try await stream?.startCapture()

        return windowInfo.frame
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
