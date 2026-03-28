import AppKit
import Combine
import SwiftUI

@MainActor
final class AppController: NSObject, ObservableObject, HotkeyManagerDelegate {
    let settingsStore: SettingsStore
    let vocabularyStore: VocabularyStore
    let historyStore: HistoryStore
    let permissionManager: PermissionManager

    private let hotkeyManager = HotkeyManager()
    private let hudController = HUDController()
    private let resultPanelController = ResultPanelController()
    private let menuBarController = MenuBarController()
    private let settingsWindowController = SettingsWindowController()
    private var pipeline: DictationPipeline?
    private var eventTask: Task<Void, Never>?

    override init() {
        self.settingsStore = SettingsStore()
        self.vocabularyStore = VocabularyStore()
        self.historyStore = HistoryStore()
        self.permissionManager = PermissionManager()
        super.init()
    }

    func start() { fatalError("TODO") }
    func stop() { fatalError("TODO") }

    // HotkeyManagerDelegate
    func hotkeyPressed() { fatalError("TODO") }
    func hotkeyReleased() { fatalError("TODO") }
}
