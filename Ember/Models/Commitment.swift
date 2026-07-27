// Commitment.swift

import Foundation
import SwiftData

/// "You said you'd send Daniel that book." Extracted by AI or added manually.
/// Open commitments boost the nudge score and appear in nudge context.
@Model
nonisolated final class Commitment {
    #Unique<Commitment>([\.id])

    var id: UUID = UUID()
    var person: Person?
    var text: String = ""
    var dueHint: Date?
    var isDone: Bool = false
    var createdAt: Date = Date.now
    var sourceEntryID: UUID?

    init(person: Person?, text: String, dueHint: Date? = nil, sourceEntryID: UUID? = nil) {
        self.id = UUID()
        self.person = person
        self.text = text
        self.dueHint = dueHint
        self.isDone = false
        self.createdAt = .now
        self.sourceEntryID = sourceEntryID
    }
}
