// KeepInTouchAssignment.swift

import Foundation
import SwiftData

/// The one write path for a person's keep-in-touch choice — never set `tier` or
/// `isPartnerMode` from a view directly. Owns the one-partner rule: choosing
/// `.partner` quietly moves the flag off whoever held it, wherever the choice
/// is made. Relations never call this (§6.4: labels never touch partner mode).
enum KeepInTouchAssignment {
    /// Applies `choice` to `person` and saves. `person` must already be inserted.
    static func apply(_ choice: KeepInTouch, to person: Person, context: ModelContext) {
        if choice.isPartner {
            clearPartner(except: person.id, context: context)
        }
        person.isPartnerMode = choice.isPartner
        if let tier = choice.tier {
            person.tier = tier
        }
        try? context.save()
    }

    /// Inserts new people from the add flows, honouring the one-partner rule
    /// across both the drafts and everyone already in Ember.
    static func insert(_ drafts: [PersonDraft], context: ModelContext) {
        for draft in drafts {
            let person = Person(
                contactID: draft.contactID,
                displayNameCache: draft.displayName,
                tier: draft.tier
            )
            context.insert(person)
            if draft.isPartner {
                apply(.partner, to: person, context: context)
            }
        }
        try? context.save()
    }

    /// The current partner, if any — for "moves the ♥ from …" copy.
    static func currentPartner(context: ModelContext) -> Person? {
        let descriptor = FetchDescriptor<Person>(predicate: #Predicate { $0.isPartnerMode == true })
        return (try? context.fetch(descriptor))?.first
    }

    private static func clearPartner(except personID: UUID, context: ModelContext) {
        let descriptor = FetchDescriptor<Person>(predicate: #Predicate { $0.isPartnerMode == true })
        for other in (try? context.fetch(descriptor)) ?? [] where other.id != personID {
            other.isPartnerMode = false
        }
    }
}
