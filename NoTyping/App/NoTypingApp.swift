import SwiftUI

@main
struct NoTypingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsRootView()
                .environmentObject(appDelegate.coordinator)
                .frame(minWidth: 880, minHeight: 640)
        }
    }
}
