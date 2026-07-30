// PersonMerge.swift

import Foundation
import SwiftData

/// Person removal beyond plain delete: a full merge into a surviving Person
/// (duplicate cleanup) or irreversible anonymization behind the shared
/// placeholder. Journal prose is never rewritten — only structured links move.
enum PersonMerge {
    /// Full merge. The survivor keeps its own name, tier, and settings; adopts
    /// contact link, manual birthday, and manual relation only where it has
    /// none; the partner flag transfers if the source was the partner (still
    /// unique — the source is deleted). Children, journal mentions (deduped),
    /// and the NudgeLog history all move, so nudge cooldowns carry over.
    static func merge(_ source: Person, into target: Person, context: ModelContext) {
        guard source.id != target.id else { return }

        for interaction in Array(source.interactions) { interaction.person = target }
        for commitment in Array(source.commitments) { commitment.person = target }
        for idea in Array(source.ideas) { idea.person = target }
        for customDate in Array(source.customDates) { customDate.person = target }

        reassignMentions(of: source, to: target)

        let logs = (try? context.fetch(FetchDescriptor<NudgeLog>())) ?? []
        for log in logs where log.personID == source.id {
            log.personID = target.id
        }

        if target.contactID == nil { target.contactID = source.contactID }
        if target.manualBirthday == nil { target.manualBirthday = source.manualBirthday }
        if target.manualRelationRaw == nil { target.manualRelationRaw = source.manualRelationRaw }
        if source.isPartnerMode { target.isPartnerMode = true }

        context.delete(source)
        try? context.save()
    }

    /// Irreversible: journal mentions swap to the shared placeholder, then the
    /// person is deleted (cascade removes interactions, commitments, ideas, and
    /// dates). The entry text itself stays exactly as the user wrote it.
    static func anonymize(_ person: Person, context: ModelContext) {
        reassignMentions(of: person, to: placeholder(in: context))
        context.delete(person)
        try? context.save()
    }

    /// The single hidden tombstone Person all anonymized mentions share.
    static func placeholder(in context: ModelContext) -> Person {
        let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        if let existing = people.first(where: { $0.isPlaceholder }) { return existing }
        let placeholder = Person(displayNameCache: String(localized: "Someone"), tier: .paused)
        placeholder.isPlaceholder = true
        context.insert(placeholder)
        return placeholder
    }

    /// Tombstones exist only to hold anonymized mentions; once the last mention
    /// is removed the placeholder is deleted (recreated on demand by
    /// `placeholder(in:)` if a future anonymize needs one).
    static func deleteOrphanedPlaceholders(context: ModelContext) {
        let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        for person in people where person.isPlaceholder && person.mentions.isEmpty {
            context.delete(person)
        }
    }

    private static func reassignMentions(of source: Person, to target: Person) {
        // Copy first: mutating entry.mentions also mutates the inverse
        // (source.mentions) mid-iteration.
        for entry in Array(source.mentions) {
            entry.mentions.removeAll { $0.id == source.id }
            if !entry.mentions.contains(where: { $0.id == target.id }) {
                entry.mentions.append(target)
            }
        }
    }
}
