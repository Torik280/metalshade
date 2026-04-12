import ScreenCaptureKit
import CoreMedia
import CoreVideo
import AppKit

final class CaptureEngine: NSObject {

    private var stream: SCStream?
    var onFrame: ((CVPixelBuffer) -> Void)?
    var excludedWindowIDs: Set<CGWindowID> = []

    static func requestPermission() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    func start() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
            guard let display = content.displays.first else { return }

            let excluded = content.windows.filter { excludedWindowIDs.contains($0.windowID) }
            let filter   = SCContentFilter(display: display, excludingWindows: excluded)

            let config = SCStreamConfiguration()
            config.pixelFormat          = kCVPixelFormatType_32BGRA
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            config.width                = display.width
            config.height               = display.height
            config.capturesAudio        = false
            if #available(macOS 14.0, *) {
                config.shouldBeOpaque   = true
            }
            config.colorSpaceName       = CGColorSpace.sRGB

            stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
            try await stream?.startCapture()
        } catch {
            print("CaptureEngine error: \(error)")
        }
    }

    func stop() {
        Task { try? await stream?.stopCapture() }
    }
}

extension CaptureEngine: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
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
