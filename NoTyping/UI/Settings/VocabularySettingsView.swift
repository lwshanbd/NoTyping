import SwiftUI
import UniformTypeIdentifiers

struct VocabularySettingsView: View {
    @EnvironmentObject private var vocabularyStore: VocabularyStore

    @State private var selectedEntryID: VocabularyEntry.ID?
    @State private var isEditing = false
    @State private var editingEntry: VocabularyEntry?
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var exportData: Data?

    var body: some View {
        VStack(spacing: 0) {
            if vocabularyStore.entries.isEmpty {
                emptyState
            } else {
                entryList
            }
            Divider()
            toolbar
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "text.book.closed")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Add your first vocabulary entry")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button {
                startAdding()
            } label: {
                Label("Add Entry", systemImage: "plus")
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Entry List

    private var entryList: some View {
        List(selection: $selectedEntryID) {
            ForEach(vocabularyStore.entries) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.writtenForm)
                        .font(.system(size: 13, weight: .medium))
                    if !entry.spokenForms.isEmpty {
                        Text(entry.spokenForms.joined(separator: ", "))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(entry.id)
                .opacity(entry.enabled ? 1.0 : 0.5)
            }
            .onDelete { offsets in
                vocabularyStore.remove(at: offsets)
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                startAdding()
            } label: {
                Image(systemName: "plus")
            }
            .help("Add entry")

            Button {
                if let id = selectedEntryID,
                   let entry = vocabularyStore.entries.first(where: { $0.id == id }) {
                    startEditing(entry)
                }
            } label: {
                Image(systemName: "pencil")
            }
            .disabled(selectedEntryID == nil)
            .help("Edit entry")

            Button {
                if let id = selectedEntryID,
                   let index = vocabularyStore.entries.firstIndex(where: { $0.id == id }) {
                    vocabularyStore.remove(at: IndexSet(integer: index))
                    selectedEntryID = nil
                }
            } label: {
                Image(systemName: "minus")
            }
            .disabled(selectedEntryID == nil)
            .help("Delete entry")

            Spacer()

            Button("Import") {
                showImporter = true
            }

            Button("Export") {
                exportData = vocabularyStore.exportJSON()
                showExporter = true
            }
            .disabled(vocabularyStore.entries.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .sheet(isPresented: $isEditing) {
            VocabularyEditSheet(
                entry: editingEntry,
                onSave: { entry in
                    if editingEntry != nil, vocabularyStore.entries.contains(where: { $0.id == entry.id }) {
                        vocabularyStore.update(entry)
                    } else {
                        vocabularyStore.add(entry)
                    }
                    isEditing = false
                    editingEntry = nil
                },
                onCancel: {
                    isEditing = false
                    editingEntry = nil
                }
            )
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                if let data = try? Data(contentsOf: url) {
                    try? vocabularyStore.importJSON(data)
                }
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: JSONDocument(data: exportData ?? Data()),
            contentType: .json,
            defaultFilename: "vocabulary.json"
        ) { _ in }
    }

    private func startAdding() {
        editingEntry = nil
        isEditing = true
    }

    private func startEditing(_ entry: VocabularyEntry) {
        editingEntry = entry
        isEditing = true
    }
}

// MARK: - Edit Sheet

private struct VocabularyEditSheet: View {
    let entry: VocabularyEntry?
    let onSave: (VocabularyEntry) -> Void
    let onCancel: () -> Void

    @State private var writtenForm: String = ""
    @State private var spokenFormsText: String = ""
    @State private var enabled: Bool = true

    var body: some View {
        VStack(spacing: 16) {
            Text(entry == nil ? "Add Vocabulary Entry" : "Edit Vocabulary Entry")
                .font(.headline)

            Form {
                TextField("Written Form", text: $writtenForm)
                    .textFieldStyle(.roundedBorder)

                TextField("Spoken Forms (comma-separated)", text: $spokenFormsText)
                    .textFieldStyle(.roundedBorder)

                Toggle("Enabled", isOn: $enabled)
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    let spokenForms = spokenFormsText
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    var newEntry = entry ?? VocabularyEntry(writtenForm: "", spokenForms: [])
                    newEntry.writtenForm = writtenForm
                    newEntry.spokenForms = spokenForms
                    newEntry.enabled = enabled
                    onSave(newEntry)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(writtenForm.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            if let entry {
                writtenForm = entry.writtenForm
                spokenFormsText = entry.spokenForms.joined(separator: ", ")
                enabled = entry.enabled
            }
        }
    }
}

// MARK: - File Document for export

private struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
