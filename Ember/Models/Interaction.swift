// Interaction.swift

import Foundation
import SwiftData

/// "I actually communicated with this person." Distinct from a journal mention —
/// this is the recency signal the nudge engine scores on.
@Model
nonisolated final class Interaction {
    #Unique<Interaction>([\.id])
    #Index<Interaction>([\.date])

    var id: UUID = UUID()
    var person: Person?
    var date: Date = Date.now
    var dateIsApproximate: Bool = false
    var channel: Channel = Channel.inPerson
    var note: String?
    var sourceEntryID: UUID?

    init(
        person: Person?,
        date: Date = .now,
        dateIsApproximate: Bool = false,
        channel: Channel,
        note: String? = nil,
        sourceEntryID: UUID? = nil
    ) {
        self.id = UUID()
        self.person = person
        self.date = date
        self.dateIsApproximate = dateIsApproximate
        self.channel = channel
        self.note = note
        self.sourceEntryID = sourceEntryID
    }
}

nonisolated enum Channel: Int, Codable, CaseIterable, Sendable {
    case inPerson = 0
    case call = 1
    case message = 2
    case other = 3

    var title: String {
        switch self {
        case .inPerson: String(localized: "In person")
        case .call: String(localized: "Call")
        case .message: String(localized: "Message")
        case .other: String(localized: "Other")
        }
    }

    var symbolName: String {
        switch self {
        case .inPerson: "figure.2"
        case .call: "phone"
        case .message: "message"
        case .other: "bubble.left.and.bubble.right"
        }
    }
}
