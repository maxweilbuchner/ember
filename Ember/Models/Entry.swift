// Entry.swift

import Foundation
import SwiftData

/// A timestamped journal entry; multiple entries per day are allowed.
/// `imageFilenames` holds filenames only — resolved against Application Support
/// at runtime (absolute paths break on container UUID change).
@Model
nonisolated final class Entry {
    #Unique<Entry>([\.id])
    #Index<Entry>([\.date])

    var id: UUID = UUID()
    var date: Date = Date.now
    var text: String = ""
    var imageFilenames: [String] = []
    var extractionState: ExtractionState = ExtractionState.pending

    @Relationship
    var mentions: [Person] = []

    init(date: Date = .now, text: String, extractionState: ExtractionState = .pending) {
        self.id = UUID()
        self.date = date
        self.text = text
        self.extractionState = extractionState
    }

    /// The first line doubles as the preview title (entries have no titles by design).
    var previewLine: String {
        text.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
    }
}

nonisolated enum ExtractionState: Int, Codable, Sendable {
    case pending = 0
    case reviewed = 1
    case skipped = 2
}
