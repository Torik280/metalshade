import ScreenCaptureKit
import CoreMedia
import CoreVideo
import AppKit

// MARK: - CaptureEngine
//
// Wraps ScreenCaptureKit.  Delivers CVPixelBuffer frames at display refresh rate.
// The overlay window and control panel are excluded from capture to avoid feedback loops.

final class CaptureEngine: NSObject {

    private var stream: SCStream?
    var onFrame: ((CVPixelBuffer) -> Void)?

    // Window IDs to exclude from the capture (our own overlay + panel)
    var excludedWindowIDs: Set<CGWindowID> = []

    // MARK: - Permission

    static func requestPermission() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    // MARK: - Start

    func start() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
            guard let display = content.displays.first else {
                print("MetalShade: no display found")
                return
            }

            // Exclude our own windows so the captured image never contains the overlay
            let excluded = content.windows.filter { excludedWindowIDs.contains($0.windowID) }
            let filter   = SCContentFilter(display: display, excludingWindows: excluded)

            let config = SCStreamConfiguration()
            config.pixelFormat                = kCVPixelFormatType_32BGRA
            config.minimumFrameInterval       = CMTime(value: 1, timescale: 60)  // max 60 fps
            config.width                      = display.width
            config.height                     = display.height
            config.capturesAudio              = false
            config.shouldBeOpaque             = true
            // Use colorspace that matches the Metal pipeline
            config.colorSpaceName             = CGColorSpace.sRGB

            stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream?.addStreamOutput(
                self,
                type: .screen,
                sampleHandlerQueue: .global(qos: .userInteractive)
            )
            try await stream?.startCapture()
        } catch {
            print("MetalShade: capture start failed — \(error)")
        }
    }

    // MARK: - Stop

    func stop() {
        Task { try? await stream?.stopCapture() }
    }
}

// MARK: - SCStreamOutput

extension CaptureEngine: SCStreamOutput {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              CMSampleBufferIsValid(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        onFrame?(pixelBuffer)
    }
}

// MARK: - SCStreamDelegate

extension CaptureEngine: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("MetalShade: stream stopped — \(error.localizedDescription)")
    }
}
