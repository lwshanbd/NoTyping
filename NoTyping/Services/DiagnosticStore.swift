import Combine
import Foundation
import OSLog

@MainActor
final class DiagnosticStore: ObservableObject {
    @Published private(set) var entries: [DiagnosticEntry] = []
    private let logger = Logger(subsystem: "com.baodi.NoTyping", category: "app")
    private weak var settingsStore: SettingsStore?

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    func record(subsystem: String, message: String) {
        logger.log("\(subsystem, privacy: .public): \(message, privacy: .public)")
        let entry = DiagnosticEntry(timestamp: .now, subsystem: subsystem, message: message)
        entries.insert(entry, at: 0)
        if entries.count > 400 {
            entries = Array(entries.prefix(400))
        }
        persistIfEnabled(entry)
    }

    func clear() {
        entries.removeAll()
        try? FileManager.default.removeItem(at: FileLocations.diagnosticsURL)
    }

    private func persistIfEnabled(_ entry: DiagnosticEntry) {
        guard settingsStore?.settings.debugLoggingEnabled == true else { return }
        let line = "[\(entry.timestamp.ISO8601Format())] [\(entry.subsystem)] \(entry.message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: FileLocations.diagnosticsURL.path) {
                if let handle = try? FileHandle(forWritingTo: FileLocations.diagnosticsURL) {
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: FileLocations.diagnosticsURL)
            }
        }
    }
}
