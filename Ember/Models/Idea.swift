// Idea.swift

import Foundation
import SwiftData

/// Simple per-person list item (gift ideas, topics to raise). Identity by `id` only.
@Model
nonisolated final class Idea {
    #Unique<Idea>([\.id])

    var id: UUID = UUID()
    var person: Person?
    var text: String = ""
    var isDone: Bool = false
    var createdAt: Date = Date.now

    init(person: Person?, text: String) {
        self.id = UUID()
        self.person = person
        self.text = text
        self.isDone = false
        self.createdAt = .now
    }
}
