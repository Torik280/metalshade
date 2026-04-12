// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MetalShade",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MetalShade",
            path: "Sources/MetalShade",
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
