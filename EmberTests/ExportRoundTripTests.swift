// ExportRoundTripTests.swift

import Foundation
import SwiftData
import Testing
@testable import Ember

@MainActor
@Suite("Export & delete everything")
struct ExportRoundTripTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    private func seed(_ container: ModelContainer) throws -> (personID: UUID, entryID: UUID) {
        let context = container.mainContext
        let person = Person(contactID: "c1", displayNameCache: "Anna", tier: .close)
        person.manualBirthday = DateComponents(month: 6, day: 15)
        person.manualRelation = .friend
        let entry = Entry(text: "Coffee with Anna — she got the offer!")
        entry.imageFilenames = ["photo.jpg"]
        entry.mentions = [person]
        context.insert(person)
        context.insert(entry)
        context.insert(Interaction(person: person, channel: .inPerson, note: "coffee", sourceEntryID: entry.id))
        context.insert(Commitment(person: person, text: "send case prep notes"))
        context.insert(Idea(person: person, text: "birthday hike"))
        context.insert(CustomDate(person: person, label: "Anniversary", month: 9, day: 3, year: 2019))
        context.insert(NudgeLog(personID: person.id, score: 2.0, reason: "It's been a while"))
        context.insert(NudgeRun(date: .now, selectedCount: 1))
        context.insert(DateAlertRecord(identifier: "birthday-seed-2026-06-15-day"))
        try context.save()
        return (person.id, entry.id)
    }

    @Test func exportCapturesEveryEntityWithFidelity() async throws {
        let container = try makeContainer()
        let seeded = try seed(container)

        let service = ExportService(container: container)
        let export = await service.buildExport()

        #expect(export.version == 2)
        #expect(export.people.count == 1)
        #expect(export.entries.count == 1)
        #expect(export.interactions.count == 1)
        #expect(export.commitments.count == 1)
        #expect(export.ideas.count == 1)
        #expect(export.customDates.count == 1)
        #expect(export.nudgeLogs.count == 1)

        let customDate = try #require(export.customDates.first)
        #expect(customDate.personID == seeded.personID)
        #expect(customDate.label == "Anniversary")
        #expect(customDate.month == 9)
        #expect(customDate.day == 3)
        #expect(customDate.year == 2019)

        let person = try #require(export.people.first)
        #expect(person.id == seeded.personID)
        #expect(person.displayName == "Anna")
        #expect(person.tier == CadenceTier.close.rawValue)
        #expect(person.birthdayMonth == 6)
        #expect(person.birthdayDay == 15)
        #expect(person.relation == "friend")

        let entry = try #require(export.entries.first)
        #expect(entry.id == seeded.entryID)
        #expect(entry.mentionPersonIDs == [seeded.personID])
        #expect(entry.imageFilenames == ["photo.jpg"])

        #expect(export.interactions.first?.personID == seeded.personID)
        #expect(export.interactions.first?.sourceEntryID == seeded.entryID)
    }

    @Test func exportJSONRoundTripsThroughCodable() async throws {
        let container = try makeContainer()
        _ = try seed(container)

        let service = ExportService(container: container)
        let export = await service.buildExport()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(EmberExport.self, from: encoder.encode(export))

        #expect(decoded.people.count == export.people.count)
        #expect(decoded.entries.first?.text == export.entries.first?.text)
        #expect(decoded.people.first?.id == export.people.first?.id)
    }

    @Test func exportZipIsCreatedAndNonEmpty() async throws {
        let container = try makeContainer()
        _ = try seed(container)

        let service = ExportService(container: container)
        let zipURL = try await service.exportZip()

        #expect(FileManager.default.fileExists(atPath: zipURL.path))
        let size = (try FileManager.default.attributesOfItem(atPath: zipURL.path)[.size] as? Int) ?? 0
        #expect(size > 100, "zip should contain the JSON document")
        #expect(zipURL.pathExtension == "zip")
        try? FileManager.default.removeItem(at: zipURL)
    }

    @Test func deleteEverythingEmptiesTheStore() async throws {
        let container = try makeContainer()
        _ = try seed(container)

        let service = ExportService(container: container)
        await service.deleteEverything()

        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<Person>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Entry>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Interaction>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Commitment>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Idea>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<CustomDate>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<NudgeLog>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<NudgeRun>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<DateAlertRecord>()).isEmpty)
    }
}
