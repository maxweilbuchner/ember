// Person.swift

import Foundation
import SwiftData

/// The app-owned representation of a human. Does NOT duplicate Contacts data:
/// `contactID` is a reference resolved live via ContactService; a Person whose
/// contact was deleted or merged survives as "unlinked" with journal history intact.
@Model
nonisolated final class Person {
    #Unique<Person>([\.id])

    var id: UUID = UUID()
    var contactID: String?
    var displayNameCache: String = ""
    var tier: CadenceTier = CadenceTier.regular
    var isPartnerMode: Bool = false
    // SwiftData cannot persist DateComponents (its embedded Calendar asserts at
    // schema build), so the manual birthday is stored as plain fields.
    var manualBirthdayMonth: Int?
    var manualBirthdayDay: Int?
    var manualBirthdayYear: Int?
    var createdAt: Date = Date.now

    /// Only used when the person is not linked to a contact.
    var manualBirthday: DateComponents? {
        get {
            guard let month = manualBirthdayMonth, let day = manualBirthdayDay else { return nil }
            return DateComponents(year: manualBirthdayYear, month: month, day: day)
        }
        set {
            manualBirthdayMonth = newValue?.month
            manualBirthdayDay = newValue?.day
            manualBirthdayYear = newValue?.year
        }
    }

    @Relationship(deleteRule: .cascade, inverse: \Interaction.person)
    var interactions: [Interaction] = []

    @Relationship(deleteRule: .cascade, inverse: \Commitment.person)
    var commitments: [Commitment] = []

    @Relationship(deleteRule: .cascade, inverse: \Idea.person)
    var ideas: [Idea] = []

    @Relationship(inverse: \Entry.mentions)
    var mentions: [Entry] = []

    init(
        contactID: String? = nil,
        displayNameCache: String,
        tier: CadenceTier = .regular,
        isPartnerMode: Bool = false,
        manualBirthday: DateComponents? = nil
    ) {
        self.id = UUID()
        self.contactID = contactID
        self.displayNameCache = displayNameCache
        self.tier = tier
        self.isPartnerMode = isPartnerMode
        self.manualBirthdayMonth = manualBirthday?.month
        self.manualBirthdayDay = manualBirthday?.day
        self.manualBirthdayYear = manualBirthday?.year
        self.createdAt = .now
    }
}

nonisolated enum CadenceTier: Int, Codable, CaseIterable, Sendable {
    case close = 0
    case regular = 1
    case orbit = 2
    case paused = 3

    /// Target cadence in days; `nil` means never nudged.
    var cadenceDays: Int? {
        switch self {
        case .close: 14
        case .regular: 45
        case .orbit: 120
        case .paused: nil
        }
    }

    var title: String {
        switch self {
        case .close: String(localized: "Close")
        case .regular: String(localized: "Regular")
        case .orbit: String(localized: "Orbit")
        case .paused: String(localized: "Paused")
        }
    }
}
