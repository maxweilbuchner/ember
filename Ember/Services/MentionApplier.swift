// MentionApplier.swift

import Foundation
import SwiftData

/// Turns extraction suggestions into data. Unambiguous matches to people Ember
/// already knows are applied automatically and reversibly (spec §4.2); anything
/// that would create a Person, or that is ambiguous, stays a suggestion until
/// the user taps it. Every mention write in the app goes through here.
@MainActor
enum MentionApplier {
    /// Applies the confident mentions (and their interactions) and returns what
    /// still needs a human. Idempotent: re-running adds no duplicates.
    static func autoApply(
        _ suggestions: EntrySuggestions,
        to entry: Entry,
        people: [Person],
        context: ModelContext
    ) -> EntrySuggestions {
        var remaining = suggestions
        remaining.mentions = suggestions.mentions.filter { mention in
            // Only .person outcomes: never silently add someone to People.
            guard case .person(let id) = mention.outcome,
                  let person = people.first(where: { $0.id == id }) else { return true }
            attach(person, to: entry, mention: mention, context: context)
            return false
        }
        return remaining
    }

    /// One tapped chip → one immediate write. Returns the person it resolved to,
    /// creating them when the suggestion pointed at a contact or a new name.
    @discardableResult
    static func apply(
        _ mention: MentionSuggestion,
        pickedPersonID: UUID? = nil,
        to entry: Entry,
        people: [Person],
        context: ModelContext
    ) -> Person? {
        guard let person = materialise(mention, pickedPersonID: pickedPersonID, people: people, context: context) else {
            return nil
        }
        attach(person, to: entry, mention: mention, context: context)
        return person
    }

    static func apply(
        _ commitment: CommitmentSuggestion,
        to entry: Entry,
        people: [Person],
        context: ModelContext
    ) {
        let owner: Person?
        if case .person(let id) = commitment.personOutcome {
            owner = people.first { $0.id == id }
        } else if let name = commitment.personName {
            owner = people.first { NameMatcher.fold($0.displayNameCache).hasPrefix(NameMatcher.fold(name)) }
        } else {
            owner = nil
        }
        context.insert(Commitment(person: owner, text: commitment.text, sourceEntryID: entry.id))
        try? context.save()
    }

    /// Undo a tag: drop the mention and the interaction this entry sourced —
    /// interactions logged elsewhere for the same person are left alone.
    static func untag(_ person: Person, from entry: Entry, context: ModelContext) {
        entry.mentions.removeAll { $0.id == person.id }
        for interaction in person.interactions where interaction.sourceEntryID == entry.id {
            context.delete(interaction)
        }
        try? context.save()
    }

    // MARK: Private

    private static func attach(
        _ person: Person,
        to entry: Entry,
        mention: MentionSuggestion,
        context: ModelContext
    ) {
        if !entry.mentions.contains(where: { $0.id == person.id }) {
            entry.mentions.append(person)
        }
        // The model flagged real contact — log it once per entry and person.
        if mention.interacted,
           !person.interactions.contains(where: { $0.sourceEntryID == entry.id }) {
            context.insert(Interaction(
                person: person,
                date: entry.date,
                channel: mention.channelGuess,
                note: mention.lifeEvent,
                sourceEntryID: entry.id
            ))
        }
        try? context.save()
    }

    private static func materialise(
        _ mention: MentionSuggestion,
        pickedPersonID: UUID?,
        people: [Person],
        context: ModelContext
    ) -> Person? {
        if let pickedPersonID {
            if let existing = people.first(where: { $0.id == pickedPersonID }) { return existing }
        }
        switch mention.outcome {
        case .person(let id):
            return people.first { $0.id == id }
        case .ambiguousPersons:
            return nil // needs a pick
        case .contact(let candidate):
            return findOrCreate(from: candidate, people: people, context: context)
        case .ambiguousContacts(let candidates):
            guard let pickedPersonID,
                  let candidate = candidates.first(where: { deterministicUUID(for: $0.id) == pickedPersonID }) else {
                return nil
            }
            return findOrCreate(from: candidate, people: people, context: context)
        case .unknown:
            let person = Person(displayNameCache: mention.name)
            context.insert(person)
            return person
        }
    }

    private static func findOrCreate(from candidate: NameCandidate, people: [Person], context: ModelContext) -> Person {
        if let existing = people.first(where: { $0.contactID == candidate.id }) {
            return existing
        }
        let person = Person(contactID: candidate.id, displayNameCache: candidate.displayName)
        context.insert(person)
        return person
    }

    /// Stable placeholder IDs so ambiguous-contact options can round-trip through
    /// the picker before a Person exists.
    static func deterministicUUID(for contactID: String) -> UUID {
        var hasher = Hasher()
        hasher.combine(contactID)
        let seed = UInt64(bitPattern: Int64(hasher.finalize()))
        return UUID(uuidString: String(format: "%08X-0000-4000-8000-%012llX", UInt32(truncatingIfNeeded: seed), seed & 0xFFFF_FFFF_FFFF)) ?? UUID()
    }
}
