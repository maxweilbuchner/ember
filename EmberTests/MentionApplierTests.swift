// MentionApplierTests.swift

import Foundation
import SwiftData
import Testing
@testable import Ember

/// The auto-tagging contract (spec §4.2): confident matches to people Ember
/// already knows are applied for you and reversibly; anything that would create
/// a Person, or that is ambiguous, waits for a tap.
@MainActor
@Suite("Mention applier")
struct MentionApplierTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    private func mention(
        _ name: String,
        outcome: NameResolutionOutcome,
        interacted: Bool = false,
        lifeEvent: String? = nil
    ) -> MentionSuggestion {
        MentionSuggestion(
            name: name,
            outcome: outcome,
            interacted: interacted,
            channelGuess: .inPerson,
            lifeEvent: lifeEvent
        )
    }

    private func suggestions(
        _ entry: Entry,
        mentions: [MentionSuggestion] = [],
        commitments: [CommitmentSuggestion] = []
    ) -> EntrySuggestions {
        EntrySuggestions(entryID: entry.id, mentions: mentions, commitments: commitments)
    }

    // MARK: Auto-apply

    @Test func autoAppliesKnownPersonAndLogsFlaggedInteraction() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let anna = Person(displayNameCache: "Anna")
        let entry = Entry(text: "Coffee with Anna")
        context.insert(anna)
        context.insert(entry)
        try context.save()

        let remaining = MentionApplier.autoApply(
            suggestions(entry, mentions: [mention("Anna", outcome: .person(anna.id), interacted: true, lifeEvent: "got the job")]),
            to: entry,
            people: [anna],
            context: context
        )

        #expect(remaining.mentions.isEmpty, "a known person needs no confirmation")
        #expect(entry.mentions.map(\.id) == [anna.id])
        let interactions = try context.fetch(FetchDescriptor<Interaction>())
        #expect(interactions.count == 1)
        #expect(interactions.first?.sourceEntryID == entry.id)
        #expect(interactions.first?.note == "got the job")
    }

    @Test func mereMentionDoesNotLogAnInteraction() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let anna = Person(displayNameCache: "Anna")
        let entry = Entry(text: "Anna's exhibition opens soon")
        context.insert(anna)
        context.insert(entry)
        try context.save()

        _ = MentionApplier.autoApply(
            suggestions(entry, mentions: [mention("Anna", outcome: .person(anna.id), interacted: false)]),
            to: entry,
            people: [anna],
            context: context
        )

        #expect(entry.mentions.count == 1)
        #expect(try context.fetch(FetchDescriptor<Interaction>()).isEmpty, "talked about ≠ talked to")
    }

    @Test func neverAutoCreatesPeopleOrResolvesAmbiguity() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let entry = Entry(text: "Lunch with Léo and Max")
        context.insert(entry)
        try context.save()

        let candidate = NameCandidate(id: "c1", givenName: "Léo", familyName: "", nickname: "", displayName: "Léo")
        let remaining = MentionApplier.autoApply(
            suggestions(entry, mentions: [
                mention("Léo", outcome: .contact(candidate)),
                mention("Max", outcome: .ambiguousPersons([UUID(), UUID()])),
                mention("Nobody", outcome: .unknown),
            ]),
            to: entry,
            people: [],
            context: context
        )

        #expect(remaining.mentions.count == 3, "all three still need a tap")
        #expect(entry.mentions.isEmpty)
        #expect(try context.fetch(FetchDescriptor<Person>()).isEmpty, "nobody is added to People behind the user's back")
    }

    @Test func autoApplyIsIdempotent() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let anna = Person(displayNameCache: "Anna")
        let entry = Entry(text: "Coffee with Anna")
        context.insert(anna)
        context.insert(entry)
        try context.save()

        let input = suggestions(entry, mentions: [mention("Anna", outcome: .person(anna.id), interacted: true)])
        _ = MentionApplier.autoApply(input, to: entry, people: [anna], context: context)
        _ = MentionApplier.autoApply(input, to: entry, people: [anna], context: context)

        #expect(entry.mentions.count == 1, "a retry must not duplicate the tag")
        #expect(try context.fetch(FetchDescriptor<Interaction>()).count == 1, "nor the interaction")
    }

    // MARK: Tapped chips

    @Test func tappedContactChipCreatesLinkedPersonAndUnknownCreatesUnlinked() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let entry = Entry(text: "Lunch with Léo and Nobody")
        context.insert(entry)
        try context.save()

        let candidate = NameCandidate(id: "c-leo", givenName: "Léo", familyName: "", nickname: "", displayName: "Léo Martin")
        let leo = MentionApplier.apply(mention("Léo", outcome: .contact(candidate)), to: entry, people: [], context: context)
        #expect(leo?.contactID == "c-leo")
        #expect(leo?.displayNameCache == "Léo Martin")

        let stranger = MentionApplier.apply(mention("Nobody", outcome: .unknown), to: entry, people: [], context: context)
        #expect(stranger?.contactID == nil)
        #expect(stranger?.displayNameCache == "Nobody")
        #expect(entry.mentions.count == 2)
    }

    @Test func ambiguousMentionAppliesThePickedPerson() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let maxA = Person(displayNameCache: "Max Weilbuchner")
        let maxB = Person(displayNameCache: "Max Berger")
        let entry = Entry(text: "Called Max")
        context.insert(maxA)
        context.insert(maxB)
        context.insert(entry)
        try context.save()

        MentionApplier.apply(
            mention("Max", outcome: .ambiguousPersons([maxA.id, maxB.id])),
            pickedPersonID: maxB.id,
            to: entry,
            people: [maxA, maxB],
            context: context
        )

        #expect(entry.mentions.map(\.id) == [maxB.id])
    }

    @Test func commitmentAttachesToItsOwner() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let anna = Person(displayNameCache: "Anna")
        let entry = Entry(text: "Told Anna I'd send my Lisbon list")
        context.insert(anna)
        context.insert(entry)
        try context.save()

        MentionApplier.apply(
            CommitmentSuggestion(text: "send the Lisbon list", personName: "Anna", personOutcome: .person(anna.id)),
            to: entry,
            people: [anna],
            context: context
        )

        let commitments = try context.fetch(FetchDescriptor<Commitment>())
        #expect(commitments.count == 1)
        #expect(commitments.first?.person?.id == anna.id)
        #expect(commitments.first?.sourceEntryID == entry.id)
    }

    // MARK: Undo

    @Test func untagRemovesOnlyWhatThisEntryWrote() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let anna = Person(displayNameCache: "Anna")
        let entry = Entry(text: "Coffee with Anna")
        context.insert(anna)
        context.insert(entry)
        // An interaction logged by hand, unrelated to this entry.
        context.insert(Interaction(person: anna, date: .now.addingTimeInterval(-86_400), channel: .call))
        try context.save()

        _ = MentionApplier.autoApply(
            suggestions(entry, mentions: [mention("Anna", outcome: .person(anna.id), interacted: true)]),
            to: entry,
            people: [anna],
            context: context
        )
        #expect(try context.fetch(FetchDescriptor<Interaction>()).count == 2)

        MentionApplier.untag(anna, from: entry, context: context)

        #expect(entry.mentions.isEmpty)
        let survivors = try context.fetch(FetchDescriptor<Interaction>())
        #expect(survivors.count == 1, "the hand-logged interaction survives")
        #expect(survivors.first?.sourceEntryID == nil)
        #expect(try context.fetch(FetchDescriptor<Person>()).count == 1, "untagging never deletes the person")
    }
}
