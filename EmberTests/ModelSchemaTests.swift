// ModelSchemaTests.swift

import Foundation
import SwiftData
import Testing
@testable import Ember

@MainActor
@Suite("Model schema")
struct ModelSchemaTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    @Test func cadenceTable() {
        #expect(CadenceTier.close.cadenceDays == 14)
        #expect(CadenceTier.regular.cadenceDays == 45)
        #expect(CadenceTier.orbit.cadenceDays == 120)
        #expect(CadenceTier.paused.cadenceDays == nil)
    }

    @Test func personRoundTrip() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let person = Person(contactID: "abc", displayNameCache: "Anna", tier: .close)
        person.manualBirthday = DateComponents(month: 6, day: 15)
        context.insert(person)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Person>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.displayNameCache == "Anna")
        #expect(fetched.first?.tier == .close)
        #expect(fetched.first?.manualBirthday?.month == 6)
        #expect(fetched.first?.isPartnerMode == false)
    }

    @Test func deletingPersonCascadesOwnedRecords() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let person = Person(displayNameCache: "Daniel")
        context.insert(person)
        context.insert(Interaction(person: person, channel: .call))
        context.insert(Commitment(person: person, text: "send the book"))
        context.insert(Idea(person: person, text: "birthday hike"))
        try context.save()

        context.delete(person)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Interaction>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Commitment>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Idea>()).isEmpty)
    }

    @Test func deletingPersonKeepsJournalEntries() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let person = Person(displayNameCache: "Julia")
        let entry = Entry(text: "Coffee with Julia — she got the offer!")
        entry.mentions = [person]
        context.insert(person)
        context.insert(entry)
        try context.save()

        context.delete(person)
        try context.save()

        let entries = try context.fetch(FetchDescriptor<Entry>())
        #expect(entries.count == 1)
        #expect(entries.first?.mentions.isEmpty == true)
    }

    @Test func entrySupportsMultiplePerDayAndImageFilenames() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let morning = Entry(text: "Morning walk with Cathi")
        let evening = Entry(text: "Dinner at Laura's")
        evening.imageFilenames = ["a.jpg", "b.jpg"]
        context.insert(morning)
        context.insert(evening)
        try context.save()

        let entries = try context.fetch(FetchDescriptor<Entry>())
        #expect(entries.count == 2)
        #expect(entries.first { $0.text.contains("Dinner") }?.imageFilenames == ["a.jpg", "b.jpg"])
    }

    @Test func entryPreviewLineSkipsBlankLines() {
        let entry = Entry(text: "\n\n  \nActual first line\nSecond line")
        #expect(entry.previewLine == "Actual first line")
    }

    @Test func nudgeLogSurvivesPersonDeletion() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let person = Person(displayNameCache: "Anna")
        context.insert(person)
        context.insert(NudgeLog(personID: person.id, score: 2.0, reason: "It's been a while"))
        try context.save()

        context.delete(person)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<NudgeLog>()).count == 1)
    }
}
