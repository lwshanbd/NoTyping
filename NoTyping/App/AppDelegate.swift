import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator(container: .live())
    private let isRunningUnderTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningUnderTests else { return }
        coordinator.start()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard !isRunningUnderTests else { return }
        coordinator.refreshPermissionStatus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !isRunningUnderTests else { return }
        coordinator.stop()
    }
}
