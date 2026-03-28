import Foundation

enum FileLocations {
    static let appSupportDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("NoTypingV2", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let settingsFile = appSupportDir.appendingPathComponent("settings.json")
    static let vocabularyFile = appSupportDir.appendingPathComponent("vocabulary.json")
    static let historyFile = appSupportDir.appendingPathComponent("history.json")
}
