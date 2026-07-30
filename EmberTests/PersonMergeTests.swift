// PersonMergeTests.swift

import Foundation
import SwiftData
import Testing
@testable import Ember

@MainActor
@Suite("Person merge & anonymize")
struct PersonMergeTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    // MARK: Merge

    @Test func mergeMovesEverythingAndDeletesSource() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let source = Person(displayNameCache: "Anna (dupe)", tier: .close)
        let target = Person(displayNameCache: "Anna", tier: .orbit)
        let entry = Entry(text: "Coffee with Anna — she got the offer!")
        entry.mentions = [source]
        context.insert(source)
        context.insert(target)
        context.insert(entry)
        context.insert(Interaction(person: source, channel: .inPerson, note: "coffee"))
        context.insert(Commitment(person: source, text: "send the book"))
        context.insert(Idea(person: source, text: "birthday hike"))
        context.insert(CustomDate(person: source, label: "First met", month: 5, day: 2))
        try context.save()

        PersonMerge.merge(source, into: target, context: context)

        let people = try context.fetch(FetchDescriptor<Person>())
        #expect(people.count == 1)
        let survivor = try #require(people.first)
        #expect(survivor.displayNameCache == "Anna", "survivor keeps its own name")
        #expect(survivor.tier == .orbit, "survivor keeps its own tier")
        #expect(survivor.interactions.count == 1)
        #expect(survivor.commitments.count == 1)
        #expect(survivor.ideas.count == 1)
        #expect(survivor.customDates.count == 1)
        #expect(survivor.mentions.count == 1)
        #expect(entry.mentions.map(\.id) == [survivor.id])
        #expect(entry.text == "Coffee with Anna — she got the offer!")
    }

    @Test func mergeDedupsMentionsWhenBothTwinsWereMentioned() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let source = Person(displayNameCache: "Anna (dupe)")
        let target = Person(displayNameCache: "Anna")
        let entry = Entry(text: "Anna twice, somehow")
        entry.mentions = [source, target]
        context.insert(source)
        context.insert(target)
        context.insert(entry)
        try context.save()

        PersonMerge.merge(source, into: target, context: context)

        #expect(entry.mentions.count == 1)
        #expect(entry.mentions.first?.id == target.id)
    }

    @Test func mergeRewritesNudgeHistorySoCooldownCarries() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let source = Person(displayNameCache: "Anna (dupe)", tier: .close)
        let target = Person(displayNameCache: "Anna", tier: .close)
        context.insert(source)
        context.insert(target)
        // Target is maximally overdue; the only thing standing between them and
        // a nudge is the cooldown from the nudge the duplicate just received.
        context.insert(Interaction(person: target, date: .now.addingTimeInterval(-100 * 86_400), channel: .call))
        context.insert(NudgeLog(personID: source.id, date: .now.addingTimeInterval(-2 * 86_400), score: 2, reason: "test", outcome: .actedOn))
        try context.save()

        PersonMerge.merge(source, into: target, context: context)

        let logs = try context.fetch(FetchDescriptor<NudgeLog>())
        #expect(logs.first?.personID == target.id, "history is rewritten to the survivor")

        let engine = NudgeEngine(container: container, contacts: StubContacts(), scheduler: SchedulerSpy())
        await engine.evaluate()
        let pending = try context.fetch(FetchDescriptor<NudgeLog>()).filter { $0.outcome == .pending }
        #expect(pending.isEmpty, "survivor inherits the 14-day cooldown from the merged-away twin")
    }

    @Test func mergeAdoptsContactBirthdayAndRelationOnlyWhereMissing() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let source = Person(contactID: "c-source", displayNameCache: "Dupe", manualBirthday: DateComponents(month: 1, day: 2))
        source.manualRelation = .friend
        let keeper = Person(contactID: "c-keeper", displayNameCache: "Keeper", manualBirthday: DateComponents(month: 3, day: 4))
        keeper.manualRelation = .colleague
        let empty = Person(displayNameCache: "Empty")
        context.insert(source)
        context.insert(keeper)
        context.insert(empty)
        try context.save()

        PersonMerge.merge(source, into: keeper, context: context)
        #expect(keeper.contactID == "c-keeper", "existing values win")
        #expect(keeper.manualBirthday?.month == 3)
        #expect(keeper.manualRelation == .colleague)

        let source2 = Person(contactID: "c-source2", displayNameCache: "Dupe 2", manualBirthday: DateComponents(month: 1, day: 2))
        source2.manualRelation = .friend
        context.insert(source2)
        try context.save()

        PersonMerge.merge(source2, into: empty, context: context)
        #expect(empty.contactID == "c-source2", "missing values are adopted")
        #expect(empty.manualBirthday?.month == 1)
        #expect(empty.manualRelation == .friend)
    }

    @Test func mergeTransfersPartnerFlag() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let source = Person(displayNameCache: "Dupe", isPartnerMode: true)
        let target = Person(displayNameCache: "Partner proper")
        context.insert(source)
        context.insert(target)
        try context.save()

        PersonMerge.merge(source, into: target, context: context)

        #expect(target.isPartnerMode, "partner flag transfers; uniqueness holds because the source is gone")
        #expect(try context.fetch(FetchDescriptor<Person>()).filter(\.isPartnerMode).count == 1)
    }

    // MARK: Anonymize

    @Test func anonymizeSwapsMentionsToOneSharedPlaceholder() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let anna = Person(displayNameCache: "Anna")
        let daniel = Person(displayNameCache: "Daniel")
        let entryA = Entry(text: "Coffee with Anna")
        entryA.mentions = [anna]
        let entryD = Entry(text: "Daniel called")
        entryD.mentions = [daniel]
        context.insert(anna)
        context.insert(daniel)
        context.insert(entryA)
        context.insert(entryD)
        context.insert(Interaction(person: anna, channel: .call))
        try context.save()

        PersonMerge.anonymize(anna, context: context)
        PersonMerge.anonymize(daniel, context: context)

        let people = try context.fetch(FetchDescriptor<Person>())
        #expect(people.count == 1, "both anonymized into the one shared placeholder")
        let placeholder = try #require(people.first)
        #expect(placeholder.isPlaceholder)
        #expect(placeholder.tier == .paused, "never surfaced by any engine")
        #expect(entryA.mentions.map(\.id) == [placeholder.id])
        #expect(entryD.mentions.map(\.id) == [placeholder.id])
        #expect(entryA.text == "Coffee with Anna", "journal prose is never rewritten")
        #expect(try context.fetch(FetchDescriptor<Interaction>()).isEmpty, "children cascade away")
    }

    @Test func placeholderIsNeverNudged() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let anna = Person(displayNameCache: "Anna")
        let entry = Entry(text: "Anna")
        entry.mentions = [anna]
        context.insert(anna)
        context.insert(entry)
        context.insert(Interaction(person: anna, date: .now.addingTimeInterval(-500 * 86_400), channel: .call))
        try context.save()

        PersonMerge.anonymize(anna, context: context)

        let engine = NudgeEngine(container: container, contacts: StubContacts(), scheduler: SchedulerSpy())
        await engine.evaluate()
        #expect(try context.fetch(FetchDescriptor<NudgeLog>()).isEmpty)
    }

    @Test func orphanedPlaceholderIsDeletedAndKeptWhileMentioned() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let anna = Person(displayNameCache: "Anna")
        let entry = Entry(text: "Coffee with Anna")
        entry.mentions = [anna]
        context.insert(anna)
        context.insert(entry)
        try context.save()

        PersonMerge.anonymize(anna, context: context)
        PersonMerge.deleteOrphanedPlaceholders(context: context)
        #expect(try context.fetch(FetchDescriptor<Person>()).count == 1, "still mentioned → survives GC")

        entry.mentions = []
        PersonMerge.deleteOrphanedPlaceholders(context: context)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Person>()).isEmpty, "last mention gone → tombstone is deleted")
    }

    // MARK: Removal cleanup

    @Test func personRemovedClosesPendingLogsAndPullsNotifications() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let personID = UUID()
        context.insert(NudgeLog(personID: personID, score: 2, reason: "test", outcome: .pending, notificationID: "nudge-x-1"))
        context.insert(NudgeLog(personID: personID, date: .now.addingTimeInterval(-30 * 86_400), score: 1, reason: "old", outcome: .actedOn, notificationID: "nudge-x-0"))
        try context.save()

        let spy = SchedulerSpy()
        let engine = NudgeEngine(container: container, contacts: StubContacts(), scheduler: spy)
        await engine.personRemoved(personID)

        let logs = try context.fetch(FetchDescriptor<NudgeLog>())
        #expect(logs.filter { $0.outcome == .pending }.isEmpty)
        #expect(logs.filter { $0.outcome == .actedOn }.count == 1, "closed history is untouched")
        #expect(await spy.removedDelivered == ["nudge-x-1"])
        #expect(await spy.removedPending.contains("nudge-x-1"))
    }
}
