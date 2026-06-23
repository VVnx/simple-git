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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
