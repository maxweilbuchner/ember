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
    // The shared "Someone" tombstone that anonymized mentions point at. Hidden
    // from the people list, extraction, and pickers; kept `.paused` so no
    // engine ever surfaces it. See PersonMerge.
    var isPlaceholder: Bool = false
    // SwiftData cannot persist DateComponents (its embedded Calendar asserts at
    // schema build), so the manual birthday is stored as plain fields.
    var manualBirthdayMonth: Int?
    var manualBirthdayDay: Int?
    var manualBirthdayYear: Int?
    // Manual relation fallback — contact-derived relations are resolved live and
    // win. A display label only: never reads or writes `isPartnerMode` (§6.4).
    var manualRelationRaw: String?
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

    var manualRelation: RelationKind? {
        get { manualRelationRaw.flatMap(RelationKind.init(rawValue:)) }
        set { manualRelationRaw = newValue?.rawValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \Interaction.person)
    var interactions: [Interaction] = []

    @Relationship(deleteRule: .cascade, inverse: \Commitment.person)
    var commitments: [Commitment] = []

    @Relationship(deleteRule: .cascade, inverse: \Idea.person)
    var ideas: [Idea] = []

    @Relationship(deleteRule: .cascade, inverse: \CustomDate.person)
    var customDates: [CustomDate] = []

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

/// Manual relation-to-you labels — the fallback when no contact card supplies
/// one. Purely descriptive: `.partner`/`.spouse` here does NOT toggle Partner
/// mode, which stays its own explicit switch (spec §6.4).
nonisolated enum RelationKind: String, Codable, CaseIterable, Sendable {
    case mother, father, parent
    case sister, brother, sibling
    case daughter, son, child
    case grandparent
    case spouse, partner
    case friend, colleague

    var title: String {
        switch self {
        case .mother: String(localized: "Mother")
        case .father: String(localized: "Father")
        case .parent: String(localized: "Parent")
        case .sister: String(localized: "Sister")
        case .brother: String(localized: "Brother")
        case .sibling: String(localized: "Sibling")
        case .daughter: String(localized: "Daughter")
        case .son: String(localized: "Son")
        case .child: String(localized: "Child")
        case .grandparent: String(localized: "Grandparent")
        case .spouse: String(localized: "Spouse")
        case .partner: String(localized: "Partner")
        case .friend: String(localized: "Friend")
        case .colleague: String(localized: "Colleague")
        }
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
