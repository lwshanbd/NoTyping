import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private weak var coordinator: AppCoordinator?
    private var window: NSWindow?

    func show(for coordinator: AppCoordinator) {
        self.coordinator = coordinator
        let window = makeWindowIfNeeded(for: coordinator)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindowIfNeeded(for coordinator: AppCoordinator) -> NSWindow {
        if let window {
            return window
        }

        let rootView = SettingsRootView()
            .environmentObject(coordinator)
            .frame(minWidth: 880, minHeight: 640)
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "NoTyping Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 980, height: 700))
        window.minSize = NSSize(width: 880, height: 640)
        window.identifier = NSUserInterfaceItemIdentifier("NoTypingSettingsWindow")
        window.isReleasedWhenClosed = false
        window.center()
        window.tabbingMode = .disallowed
        window.delegate = self
        window.setFrameAutosaveName("NoTypingSettingsWindow")

        self.window = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        coordinator?.selectedSettingsTab = .general
    }
}
