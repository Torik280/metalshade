// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MetalShade",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MetalShade",
            path: "Sources/MetalShade",
            // System frameworks are auto-linked on import, but listing them
            // here makes SPM resolution explicit and avoids edge-case linker issues.
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
            ]
        )
    ]
)
