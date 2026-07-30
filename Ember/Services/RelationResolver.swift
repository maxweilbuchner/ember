// RelationResolver.swift

import Foundation

/// One labeled related-name from a contact card ("mother: Anna"). The name is
/// just a string — Contacts stores no identifier for related people, so any
/// linking back to Ember people goes through NameMatcher.
nonisolated struct ContactRelationItem: Sendable, Hashable {
    /// The CNLabelContactRelation… constant, or the user's custom label string.
    var rawLabel: String
    /// Human-readable, localized by Contacts ("Mother", "Ehefrau", …).
    var localizedLabel: String
    var name: String
}

/// A contact's related name, cross-linked to an Ember Person when the name
/// resolves to exactly one — otherwise it stays a plain text row.
nonisolated struct RelationLink: Sendable, Hashable, Identifiable {
    var localizedLabel: String
    var rawLabel: String
    var name: String
    var linkedPersonID: UUID?

    var id: String { rawLabel + "|" + name }
}

/// Pure resolution of contact relation labels against Ember's people. Relations
/// are display labels only — they never influence scoring, copy, or partner
/// mode (spec §6.4 keeps `isPartnerMode` an independent behavioural flag).
nonisolated enum RelationResolver {
    /// A Person as a matchable name candidate; `id` carries the Person UUID.
    static func candidate(personID: UUID, displayName: String) -> NameCandidate {
        let parts = displayName.split(separator: " ", maxSplits: 1).map(String.init)
        return NameCandidate(
            id: personID.uuidString,
            givenName: parts.first ?? "",
            familyName: parts.count > 1 ? parts[1] : "",
            nickname: "",
            displayName: displayName
        )
    }

    /// The label this person carries on the *user's own* card ("mother: Anna" →
    /// "Mother" on Anna's profile). Labels only on an unambiguous match: the
    /// related name must resolve to exactly this person among all people.
    static func labelForPerson(
        personID: UUID,
        meRelations: [ContactRelationItem],
        people: [NameCandidate]
    ) -> String? {
        for relation in meRelations {
            let matches = NameMatcher.resolve(name: relation.name, in: people)
            if matches.count == 1, matches[0].id == personID.uuidString {
                return relation.localizedLabel
            }
        }
        return nil
    }

    /// The person's own related names ("spouse: Tom"), cross-linked to Ember
    /// people where the name resolves uniquely. The person themself is excluded
    /// from matching (cards sometimes list their own name).
    static func related(
        relations: [ContactRelationItem],
        people: [NameCandidate],
        excludingPersonID: UUID
    ) -> [RelationLink] {
        relations.map { item in
            let matches = NameMatcher.resolve(name: item.name, in: people)
                .filter { $0.id != excludingPersonID.uuidString }
            return RelationLink(
                localizedLabel: item.localizedLabel,
                rawLabel: item.rawLabel,
                name: item.name,
                linkedPersonID: matches.count == 1 ? UUID(uuidString: matches[0].id) : nil
            )
        }
    }
}
