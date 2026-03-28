import AppKit
import Foundation

@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    var onSettingsClicked: (() -> Void)?
    var onQuitClicked: (() -> Void)?

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "NoTyping")
        }

        let menu = NSMenu()

        let statusLine = NSMenuItem(title: "Idle", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        self.statusMenuItem = statusLine

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(settingsAction(_:)), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit NoTyping", action: #selector(quitAction(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        self.statusItem = item
    }

    func updateStatus(_ state: PipelineState) {
        let iconName: String
        let statusText: String

        switch state {
        case .idle, .ready:
            iconName = "mic"
            statusText = "Ready"
        case .recording:
            iconName = "mic.fill"
            statusText = "Recording..."
        case .transcribing:
            iconName = "mic.fill"
            statusText = "Transcribing..."
        case .normalizing:
            iconName = "mic.fill"
            statusText = "Processing..."
        case .polishing:
            iconName = "mic.fill"
            statusText = "Polishing..."
        case .inserting:
            iconName = "mic.fill"
            statusText = "Inserting..."
        case .error:
            iconName = "mic.slash"
            statusText = "Error"
        }

        statusItem?.button?.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "NoTyping")
        statusMenuItem?.title = statusText
    }

    @objc private func settingsAction(_ sender: Any?) {
        onSettingsClicked?()
    }

    @objc private func quitAction(_ sender: Any?) {
        onQuitClicked?()
    }
}
