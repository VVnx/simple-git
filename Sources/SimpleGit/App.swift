import SwiftUI
import AppKit

@main
struct SimpleGitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 920, minHeight: 560)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("刷新") { store.reload() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(store.isRepositoryOperationInProgress)
            }
        }
    }
}

/// SwiftUI's bare-executable launch path doesn't always bring the window forward,
/// so nudge the activation policy and focus on launch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // `swift run` launches a bare executable with no bundle icon, so set the
        // Dock icon from the bundled resource at launch.
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
