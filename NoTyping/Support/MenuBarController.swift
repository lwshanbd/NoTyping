import AppKit
import Foundation

@MainActor
final class MenuBarController: NSObject {
    enum SettingsDestination {
        case general
        case vocabulary
        case permissions
        case provider
        case debug
    }

    var onToggleDictation: (() -> Void)?
    var onOpenSettings: ((SettingsDestination) -> Void)?
    var onQuit: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem(title: "Status: Idle", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "Start Dictation", action: #selector(toggleDictation), keyEquivalent: "")
    private let recentErrorItem = NSMenuItem(title: "Recent Error: None", action: nil, keyEquivalent: "")

    override init() {
        super.init()
        if let button = statusItem.button {
            button.title = "NoTyping"
        }

        toggleItem.target = self
        recentErrorItem.isEnabled = false
        statusMenuItem.isEnabled = false

        menu.addItem(toggleItem)
        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeItem(title: "Settings", action: #selector(openGeneral)))
        menu.addItem(makeItem(title: "Permissions Status", action: #selector(openPermissions)))
        menu.addItem(makeItem(title: "Vocabulary Manager", action: #selector(openVocabulary)))
        menu.addItem(makeItem(title: "Provider Settings", action: #selector(openProvider)))
        menu.addItem(makeItem(title: "Debug Panel", action: #selector(openDebug)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(recentErrorItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeItem(title: "Quit", action: #selector(quit)))
        statusItem.menu = menu
    }

    func update(status: String, isRecording: Bool, recentError: String?) {
        statusMenuItem.title = "Status: \(status)"
        toggleItem.title = isRecording ? "Stop Dictation" : "Start Dictation"
        recentErrorItem.title = "Recent Error: \(recentError ?? "None")"
    }

    private func makeItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func toggleDictation() {
        onToggleDictation?()
    }

    @objc private func openGeneral() {
        onOpenSettings?(.general)
    }

    @objc private func openVocabulary() {
        onOpenSettings?(.vocabulary)
    }

    @objc private func openPermissions() {
        onOpenSettings?(.permissions)
    }

    @objc private func openProvider() {
        onOpenSettings?(.provider)
    }

    @objc private func openDebug() {
        onOpenSettings?(.debug)
    }

    @objc private func quit() {
        onQuit?()
    }
}
