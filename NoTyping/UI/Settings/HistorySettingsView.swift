import SwiftUI

struct HistorySettingsView: View {
    @EnvironmentObject private var historyStore: HistoryStore

    @State private var searchText: String = ""
    @State private var expandedEntryID: HistoryEntry.ID?

    private var filteredEntries: [HistoryEntry] {
        if searchText.isEmpty {
            return historyStore.entries
        }
        return historyStore.search(searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search transcriptions...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.quaternary.opacity(0.5))

            Divider()

            if filteredEntries.isEmpty {
                emptyState
            } else {
                entryList
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "No transcriptions yet" : "No results found")
                .font(.headline)
                .foregroundStyle(.secondary)
            if !searchText.isEmpty {
                Text("Try a different search term")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Entry List

    private var entryList: some View {
        List {
            ForEach(filteredEntries) { entry in
                historyRow(entry)
            }
        }
    }

    @ViewBuilder
    private func historyRow(_ entry: HistoryEntry) -> some View {
        let isExpanded = expandedEntryID == entry.id
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.timestamp, style: .date)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    + Text(" ")
                    + Text(entry.timestamp, style: .time)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Text(displayText(for: entry))
                        .font(.system(size: 13))
                        .lineLimit(isExpanded ? nil : 1)
                        .truncationMode(.tail)
                }
                Spacer()
                copyButton(for: entry)
            }

            if isExpanded, let polished = entry.polishedText, polished != entry.rawText {
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Original:")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(entry.rawText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if isExpanded, let app = entry.targetApp {
                Text("App: \(app)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                expandedEntryID = isExpanded ? nil : entry.id
            }
        }
    }

    private func displayText(for entry: HistoryEntry) -> String {
        entry.polishedText ?? entry.rawText
    }

    private func copyButton(for entry: HistoryEntry) -> some View {
        CopyEntryButton(text: displayText(for: entry))
    }
}

// MARK: - Copy button with feedback

private struct CopyEntryButton: View {
    let text: String
    @State private var isCopied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            isCopied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                isCopied = false
            }
        } label: {
            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11))
                .foregroundStyle(isCopied ? .green : .secondary)
        }
        .buttonStyle(.plain)
        .help("Copy to clipboard")
    }
}
