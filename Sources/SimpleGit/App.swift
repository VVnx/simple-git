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
                Button("刷新") { store.refreshCurrentRepository() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(store.isRepositoryOperationInProgress)
            }
        }
    }
}

/// SwiftUI's bare-executable launch path doesn't always bring the window forward,
/// so nudge the activation policy and focus on launch.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var windowObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // `swift run` launches a bare executable with no bundle icon, so set the
        // Dock icon from the bundled resource at launch.
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }

        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            self?.configureCloseBehavior(for: window)
        }

        DispatchQueue.main.async { [weak self] in
            NSApp.windows.forEach { self?.configureCloseBehavior(for: $0) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        if let window = sender.windows.first(where: { isMainAppWindow($0) }) {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
            sender.activate(ignoringOtherApps: true)
            return false
        }
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.miniaturize(nil)
        return false
    }

    private func configureCloseBehavior(for window: NSWindow) {
        guard isMainAppWindow(window) else { return }
        window.delegate = self
    }

    private func isMainAppWindow(_ window: NSWindow) -> Bool {
        window.level == .normal
            && window.parent == nil
            && !window.isSheet
            && !(window is NSPanel)
            && window.styleMask.contains(.closable)
            && window.styleMask.contains(.miniaturizable)
    }
}
