// CustomDate.swift

import Foundation
import SwiftData

/// A recurring important date on a person beyond their birthday — anniversary,
/// first met, name day. Month/day (+ optional year) as plain Ints, same as the
/// manual birthday: SwiftData cannot persist DateComponents.
@Model
nonisolated final class CustomDate {
    #Unique<CustomDate>([\.id])

    var id: UUID = UUID()
    var person: Person?
    /// Free text, chosen by the user ("Anniversary", "First met").
    var label: String = ""
    var month: Int = 1
    var day: Int = 1
    var year: Int?
    var createdAt: Date = Date.now

    var components: DateComponents {
        DateComponents(year: year, month: month, day: day)
    }

    init(person: Person?, label: String, month: Int, day: Int, year: Int? = nil) {
        self.id = UUID()
        self.person = person
        self.label = label
        self.month = month
        self.day = day
        self.year = year
        self.createdAt = .now
    }
}
