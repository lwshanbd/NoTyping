import XCTest
@testable import NoTypingV2

@MainActor
final class SettingsStoreTests: XCTestCase {

    private var backupData: Data?
    private let settingsURL = FileLocations.settingsFile

    override func setUp() {
        super.setUp()
        // Back up existing settings file so tests don't clobber real data
        backupData = try? Data(contentsOf: settingsURL)
        try? FileManager.default.removeItem(at: settingsURL)
    }

    override func tearDown() {
        // Restore original settings file
        if let data = backupData {
            try? data.write(to: settingsURL, options: [.atomic])
        } else {
            try? FileManager.default.removeItem(at: settingsURL)
        }
        super.tearDown()
    }

    func testRoundTrip() {
        let store = SettingsStore()
        store.settings.hotkeyMode = .pushToTalk
        store.settings.languageMode = .simplifiedChinese
        store.settings.llmEnabled = false
        store.settings.launchAtLogin = true
        store.save()

        // Create a fresh store; it should load what we just saved
        let reloaded = SettingsStore()
        XCTAssertEqual(reloaded.settings.hotkeyMode, .pushToTalk)
        XCTAssertEqual(reloaded.settings.languageMode, .simplifiedChinese)
        XCTAssertFalse(reloaded.settings.llmEnabled)
        XCTAssertTrue(reloaded.settings.launchAtLogin)
    }

    func testDefaultSettingsWhenNoFileExists() {
        // No file on disk (removed in setUp) => defaults
        let store = SettingsStore()
        let defaults = AppSettings()
        XCTAssertEqual(store.settings, defaults)
    }

    func testAPIKeyIsolation() {
        // Use a dedicated keychain service so we don't pollute the real one
        let keychain = KeychainStore(service: "com.baodi.NoTypingV2.tests")
        let accountA = "test.account.a.\(UUID().uuidString)"
        let accountB = "test.account.b.\(UUID().uuidString)"

        // Cleanup helper
        defer {
            try? keychain.delete(account: accountA)
            try? keychain.delete(account: accountB)
        }

        try? keychain.save("secret-a", account: accountA)
        try? keychain.save("secret-b", account: accountB)

        XCTAssertEqual(keychain.load(account: accountA), "secret-a")
        XCTAssertEqual(keychain.load(account: accountB), "secret-b")

        // Loading a key for a different account must not leak
        let nonExistent = "test.account.missing.\(UUID().uuidString)"
        XCTAssertNil(keychain.load(account: nonExistent))
    }
}
