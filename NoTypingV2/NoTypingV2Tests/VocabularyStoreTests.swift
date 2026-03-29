import XCTest
@testable import NoTypingV2

@MainActor
final class VocabularyStoreTests: XCTestCase {

    private var backupData: Data?
    private let vocabURL = FileLocations.vocabularyFile

    override func setUp() {
        super.setUp()
        backupData = try? Data(contentsOf: vocabURL)
        try? FileManager.default.removeItem(at: vocabURL)
    }

    override func tearDown() {
        if let data = backupData {
            try? data.write(to: vocabURL, options: [.atomic])
        } else {
            try? FileManager.default.removeItem(at: vocabURL)
        }
        super.tearDown()
    }

    func testAddEntry() {
        let store = VocabularyStore()
        XCTAssertTrue(store.entries.isEmpty)

        let entry = VocabularyEntry(writtenForm: "Xcode", spokenForms: ["ex code"])
        store.add(entry)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.writtenForm, "Xcode")
        XCTAssertEqual(store.entries.first?.spokenForms, ["ex code"])
    }

    func testRemoveEntry() {
        let store = VocabularyStore()
        let entry = VocabularyEntry(writtenForm: "Swift", spokenForms: ["swift"])
        store.add(entry)
        XCTAssertEqual(store.entries.count, 1)

        store.remove(at: IndexSet(integer: 0))
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testUpdateEntry() {
        let store = VocabularyStore()
        var entry = VocabularyEntry(writtenForm: "OldName", spokenForms: ["old name"])
        store.add(entry)

        entry.writtenForm = "NewName"
        entry.spokenForms = ["new name", "updated name"]
        store.update(entry)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.writtenForm, "NewName")
        XCTAssertEqual(store.entries.first?.spokenForms, ["new name", "updated name"])
    }

    func testExportAndReimport() throws {
        let store = VocabularyStore()
        store.add(VocabularyEntry(writtenForm: "Alpha", spokenForms: ["alpha"]))
        store.add(VocabularyEntry(writtenForm: "Beta", spokenForms: ["beta", "bay-tah"]))

        guard let json = store.exportJSON() else {
            XCTFail("exportJSON returned nil")
            return
        }

        // Clear entries and re-import
        store.remove(at: IndexSet(integersIn: 0..<store.entries.count))
        XCTAssertTrue(store.entries.isEmpty)

        try store.importJSON(json)
        XCTAssertEqual(store.entries.count, 2)
        let forms = Set(store.entries.map(\.writtenForm))
        XCTAssertTrue(forms.contains("Alpha"))
        XCTAssertTrue(forms.contains("Beta"))
    }

    func testImportSkipsDuplicateWrittenForms() throws {
        let store = VocabularyStore()
        store.add(VocabularyEntry(writtenForm: "Duplicate", spokenForms: ["dupe"]))
        XCTAssertEqual(store.entries.count, 1)

        // Build JSON with the same writtenForm plus a new one
        let incoming: [VocabularyEntry] = [
            VocabularyEntry(writtenForm: "Duplicate", spokenForms: ["duplicate again"]),
            VocabularyEntry(writtenForm: "Unique", spokenForms: ["unique"]),
        ]
        let data = try JSONEncoder().encode(incoming)

        try store.importJSON(data)
        // "Duplicate" should NOT be added again; only "Unique" should be new
        XCTAssertEqual(store.entries.count, 2)
        let forms = store.entries.map(\.writtenForm)
        XCTAssertEqual(forms, ["Duplicate", "Unique"])
    }
}
