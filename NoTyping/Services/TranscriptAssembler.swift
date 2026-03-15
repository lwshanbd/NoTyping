import Foundation

struct TranscriptAssemblerUpdate: Equatable {
    var partialText: String?
    var finalizedSegment: TranscriptSegment?
}

final class TranscriptAssembler {
    private struct Item {
        var id: String
        var previousItemID: String?
        var partialText: String = ""
        var finalText: String?
        var averageLogProbability: Double?
        var inserted = false
    }

    private var items: [String: Item] = [:]
    private var orderedIDs: [String] = []

    func apply(_ event: TranscriptionEvent) -> TranscriptAssemblerUpdate {
        switch event {
        case .connectionStatus, .sessionCreated, .bufferCommitted:
            return TranscriptAssemblerUpdate(partialText: visibleText(), finalizedSegment: nil)
        case let .failed(_, message):
            return TranscriptAssemblerUpdate(partialText: message, finalizedSegment: nil)
        case let .partial(itemID, previousItemID, text):
            upsert(itemID: itemID, previousItemID: previousItemID)
            items[itemID]?.partialText = text
            return TranscriptAssemblerUpdate(partialText: visibleText(), finalizedSegment: nil)
        case let .completed(itemID, previousItemID, text, averageLogProbability):
            upsert(itemID: itemID, previousItemID: previousItemID)
            let alreadyFinalized = items[itemID]?.finalText == text
            items[itemID]?.partialText = text
            items[itemID]?.finalText = text
            items[itemID]?.averageLogProbability = averageLogProbability
            guard alreadyFinalized == false else {
                return TranscriptAssemblerUpdate(partialText: visibleText(), finalizedSegment: nil)
            }
            let segment = TranscriptSegment(id: itemID, previousItemID: previousItemID, rawText: text, averageLogProbability: averageLogProbability)
            return TranscriptAssemblerUpdate(partialText: visibleText(), finalizedSegment: segment)
        }
    }

    func markInserted(segmentID: String) {
        items[segmentID]?.inserted = true
    }

    func reset() {
        items.removeAll()
        orderedIDs.removeAll()
    }

    func recentContext(limit: Int = 2) -> String {
        orderedIDs.compactMap { items[$0] }
            .compactMap(\.finalText)
            .suffix(limit)
            .joined(separator: " ")
    }

    private func visibleText() -> String {
        orderedIDs.compactMap { id in
            guard let item = items[id] else { return nil }
            return item.finalText ?? item.partialText
        }
        .filter { !$0.trimmed.isEmpty }
        .joined(separator: " ")
        .collapsedWhitespace
    }

    private func upsert(itemID: String, previousItemID: String?) {
        if items[itemID] == nil {
            items[itemID] = Item(id: itemID, previousItemID: previousItemID)
            if let previousItemID,
               let index = orderedIDs.firstIndex(of: previousItemID) {
                orderedIDs.insert(itemID, at: index + 1)
            } else if !orderedIDs.contains(itemID) {
                orderedIDs.append(itemID)
            }
        }
    }
}
