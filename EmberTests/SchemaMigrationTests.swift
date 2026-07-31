// SchemaMigrationTests.swift

import Foundation
import SwiftData
import Testing
@testable import Ember

/// The rest of the suite uses `isStoredInMemoryOnly: true`, which never migrates —
/// so a broken `EmberMigrationPlan` would go unnoticed until launch, where a
/// failed `ModelContainer` init is a `fatalError`. These tests use a file-backed
/// store in a temp directory to exercise the real path.
@MainActor
@Suite("Schema migration")
struct SchemaMigrationTests {
    private func makeStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("EmberMigration-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("ember.store")
    }

    private func removeStore(at url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test func v1StoreMigratesToCurrentSchemaKeepingItsData() throws {
        let url = makeStoreURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer { removeStore(at: url) }

        let personID: UUID
        do {
            let schema = Schema(versionedSchema: SchemaV1.self)
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)]
            )
            let person = Person(displayNameCache: "Anna", tier: .close)
            personID = person.id
            container.mainContext.insert(person)
            try container.mainContext.save()
        }

        // Reopen through the migration plan — a pure add-table stage.
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: EmberMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)]
        )
        let context = container.mainContext

        let people = try context.fetch(FetchDescriptor<Person>())
        #expect(people.count == 1)
        #expect(people.first?.id == personID)
        #expect(people.first?.displayNameCache == "Anna")

        // The new entity exists and starts empty — a migrated store behaves like
        // a fresh one: no rows, both switches on.
        #expect(try context.fetch(FetchDescriptor<NotificationSettings>()).isEmpty)
        #expect(NotificationSettings.flags(in: context) == .allEnabled)
    }
}
