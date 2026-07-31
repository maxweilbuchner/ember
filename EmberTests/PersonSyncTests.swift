// PersonSyncTests.swift

import Foundation
import SwiftData
import Testing
@testable import Ember

@MainActor
@Suite("PersonSync")
struct PersonSyncTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    @Test func refreshesDisplayNameFromResolution() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let person = Person(contactID: "c1", displayNameCache: "Old Name")
        context.insert(person)
        try context.save()

        let sync = PersonSyncService(container: container, contacts: ContactService())
        await sync.apply(resolutions: [ContactResolution(contactID: "c1", displayName: "New Name")], hasFullAccess: true)

        let fetched = try context.fetch(FetchDescriptor<Person>())
        #expect(fetched.first?.displayNameCache == "New Name")
        #expect(fetched.first?.contactID == "c1")
    }

    @Test func unresolvableUnderFullAccessUnlinksButKeepsHistory() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let person = Person(contactID: "gone", displayNameCache: "Cathi")
        context.insert(person)
        context.insert(Interaction(person: person, channel: .inPerson, note: "lake swim"))
        try context.save()

        let sync = PersonSyncService(container: container, contacts: ContactService())
        await sync.apply(resolutions: [ContactResolution(contactID: "gone", displayName: nil)], hasFullAccess: true)

        let fetched = try context.fetch(FetchDescriptor<Person>())
        #expect(fetched.first?.contactID == nil, "contact deletion degrades to unlinked")
        #expect(fetched.first?.displayNameCache == "Cathi", "name cache survives")
        #expect(try context.fetch(FetchDescriptor<Interaction>()).count == 1, "history intact")
    }

    @Test func unresolvableUnderLimitedAccessStaysLinked() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let person = Person(contactID: "outside-limited-set", displayNameCache: "Laura")
        context.insert(person)
        try context.save()

        let sync = PersonSyncService(container: container, contacts: ContactService())
        await sync.apply(resolutions: [ContactResolution(contactID: "outside-limited-set", displayName: nil)], hasFullAccess: false)

        let fetched = try context.fetch(FetchDescriptor<Person>())
        #expect(fetched.first?.contactID == "outside-limited-set", "limited access must not unlink")
    }

    @Test func emptyResolvedNameDoesNotWipeCache() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let person = Person(contactID: "c2", displayNameCache: "Anna")
        context.insert(person)
        try context.save()

        let sync = PersonSyncService(container: container, contacts: ContactService())
        await sync.apply(resolutions: [ContactResolution(contactID: "c2", displayName: "")], hasFullAccess: true)

        let fetched = try context.fetch(FetchDescriptor<Person>())
        #expect(fetched.first?.displayNameCache == "Anna")
    }
}
