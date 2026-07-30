// BirthdayWriteBackTests.swift

import Foundation
import SwiftData
import Testing
@testable import Ember

/// Writing a birthday back to the contact card is opt-in, and either way Ember
/// must not lose the birthday. On success the card owns it (no duplicate left
/// behind); on failure Ember keeps it, quietly.
@MainActor
@Suite("Birthday write-back")
struct BirthdayWriteBackTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    private let june15 = DateComponents(month: 6, day: 15)

    @Test func successfulWriteHandsOwnershipToTheCard() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let person = Person(contactID: "c1", displayNameCache: "Anna")
        context.insert(person)
        try context.save()

        let writer = StubContactWriter()
        let wrote = await BirthdayWriteBack.save(
            june15, for: person, alsoToContacts: true, writer: writer, context: context
        )

        #expect(wrote)
        let writes = await writer.writes
        #expect(writes.count == 1)
        #expect(writes.first?.contactID == "c1")
        #expect(writes.first?.birthday?.month == 6)
        #expect(person.manualBirthday == nil, "the card owns it now — no second copy to drift")
    }

    @Test func failedWriteKeepsTheBirthdayInEmber() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let person = Person(contactID: "gone", displayNameCache: "Anna")
        context.insert(person)
        try context.save()

        let wrote = await BirthdayWriteBack.save(
            june15, for: person, alsoToContacts: true,
            writer: StubContactWriter(shouldFail: true), context: context
        )

        #expect(!wrote)
        #expect(person.manualBirthday?.month == 6, "a refused card write must never lose the birthday")
    }

    @Test func optedOutNeverTouchesTheAddressBook() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let person = Person(contactID: "c1", displayNameCache: "Anna")
        context.insert(person)
        try context.save()

        let writer = StubContactWriter()
        let wrote = await BirthdayWriteBack.save(
            june15, for: person, alsoToContacts: false, writer: writer, context: context
        )

        #expect(!wrote)
        #expect(await writer.writes.isEmpty, "no write without the user asking for one")
        #expect(person.manualBirthday?.month == 6)
    }

    @Test func unlinkedPersonIsNeverWrittenAnywhere() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let person = Person(displayNameCache: "Unlinked")
        context.insert(person)
        try context.save()

        let writer = StubContactWriter()
        let wrote = await BirthdayWriteBack.save(
            june15, for: person, alsoToContacts: true, writer: writer, context: context
        )

        #expect(!wrote)
        #expect(await writer.writes.isEmpty, "no contact to write to")
        #expect(person.manualBirthday?.month == 6)
    }

    @Test func removingABirthdayClearsItFromTheCardToo() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let person = Person(contactID: "c1", displayNameCache: "Anna", manualBirthday: june15)
        context.insert(person)
        try context.save()

        let writer = StubContactWriter()
        await BirthdayWriteBack.save(
            nil, for: person, alsoToContacts: true, writer: writer, context: context
        )

        let writes = await writer.writes
        #expect(writes.count == 1)
        #expect(writes.first?.birthday == nil, "removal propagates as a nil birthday")
        #expect(person.manualBirthday == nil)
    }
}
