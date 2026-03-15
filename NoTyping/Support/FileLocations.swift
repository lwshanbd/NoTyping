import Foundation

enum FileLocations {
    static let appFolderName = "NoTyping"

    static var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent(appFolderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var settingsURL: URL {
        applicationSupportDirectory.appendingPathComponent("settings.json")
    }

    static var vocabularyURL: URL {
        applicationSupportDirectory.appendingPathComponent("vocabulary.json")
    }

    static var historyURL: URL {
        applicationSupportDirectory.appendingPathComponent("history.json")
    }

    static var diagnosticsURL: URL {
        applicationSupportDirectory.appendingPathComponent("diagnostics.log")
    }
}
