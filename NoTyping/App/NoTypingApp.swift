import SwiftUI

@main
struct NoTypingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsRootView()
                .environmentObject(appDelegate.coordinator.settingsStore)
                .environmentObject(appDelegate.coordinator.vocabularyStore)
                .environmentObject(appDelegate.coordinator.historyStore)
                .environmentObject(appDelegate.coordinator.permissionManager)
                .frame(minWidth: 600, minHeight: 400)
        }
    }
}
