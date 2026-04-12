import SwiftUI
import AppKit

@main
struct MetalShadeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // No main window — we use custom NSPanel + overlay
        Settings { EmptyView() }
    }
}
