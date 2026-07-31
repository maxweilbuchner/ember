// NotificationActionTests.swift

import Foundation
import SwiftData
import Testing
@testable import Ember

@MainActor
@Suite("Nudge engine actions")
struct NotificationActionTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    private func makeEngine(_ container: ModelContainer) -> NudgeEngine {
        NudgeEngine(container: container, contacts: ContactService())
    }

    @Test func weSpokeLogsInteractionAndClosesNudge() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let person = Person(displayNameCache: "Anna", tier: .close)
        context.insert(person)
        let log = NudgeLog(personID: person.id, score: 2.0, reason: "It's been a while")
        context.insert(log)
        try context.save()

        let engine = makeEngine(container)
        await engine.handleWeSpoke(personID: person.id, nudgeLogID: log.id)

        let interactions = try context.fetch(FetchDescriptor<Interaction>())
        #expect(interactions.count == 1)
        #expect(interactions.first?.person?.id == person.id)
        let logs = try context.fetch(FetchDescriptor<NudgeLog>())
        #expect(logs.first { $0.id == log.id }?.outcome == .actedOn)
    }

    @Test func weSpokeWithoutLogIDClosesLatestPendingLog() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let person = Person(displayNameCache: "Daniel", tier: .regular)
        context.insert(person)
        let older = NudgeLog(personID: person.id, date: .now.addingTimeInterval(-86_400), score: 1.0, reason: "r1")
        let newer = NudgeLog(personID: person.id, date: .now, score: 2.0, reason: "r2")
        context.insert(older)
        context.insert(newer)
        try context.save()

        let engine = makeEngine(container)
        await engine.handleWeSpoke(personID: person.id, nudgeLogID: nil)

        let logs = try context.fetch(FetchDescriptor<NudgeLog>())
        #expect(logs.first { $0.reason == "r2" }?.outcome == .actedOn)
        #expect(logs.first { $0.reason == "r1" }?.outcome == .pending)
    }

    @Test func snoozeWritesFreshQuietWindow() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let person = Person(displayNameCache: "Cathi", tier: .close)
        context.insert(person)
        let log = NudgeLog(personID: person.id, score: 1.5, reason: "It's been a while")
        context.insert(log)
        try context.save()

        let engine = makeEngine(container)
        await engine.handleSnooze(personID: person.id, nudgeLogID: log.id)

        let logs = try context.fetch(FetchDescriptor<NudgeLog>())
        #expect(logs.count == 2, "snooze adds its own audit entry")
        #expect(logs.first { $0.id == log.id }?.outcome == .snoozed)
        #expect(logs.contains { $0.id != log.id && $0.outcome == .snoozed })
    }

    @Test func evaluateNudgesOverdueClosePerson() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let person = Person(displayNameCache: "Anna", tier: .close)
        context.insert(person)
        context.insert(Interaction(
            person: person,
            date: .now.addingTimeInterval(-30 * 86_400),
            channel: .inPerson,
            note: "coffee — she got the Bain offer"
        ))
        try context.save()

        let engine = makeEngine(container)
        await engine.evaluate()

        let logs = try context.fetch(FetchDescriptor<NudgeLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.outcome == .pending)
        #expect(abs((logs.first?.score ?? 0) - 30.0 / 14.0) < 0.01)
        let runs = try context.fetch(FetchDescriptor<NudgeRun>())
        #expect(runs.count == 1)
        #expect(runs.first?.selectedCount == 1)
    }

    @Test func evaluateStaysSilentWhenNobodyQualifies() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let person = Person(displayNameCache: "Laura", tier: .close)
        context.insert(person)
        context.insert(Interaction(person: person, date: .now.addingTimeInterval(-86_400), channel: .message))
        try context.save()

        let engine = makeEngine(container)
        await engine.evaluate()

        #expect(try context.fetch(FetchDescriptor<NudgeLog>()).isEmpty, "silence is fine")
        #expect(try context.fetch(FetchDescriptor<NudgeRun>()).count == 1, "run is still recorded")
    }

    @Test func evaluateSkipsPartnerEntirely() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let partner = Person(displayNameCache: "Partner", tier: .close, isPartnerMode: true)
        context.insert(partner)
        try context.save()

        let engine = makeEngine(container)
        await engine.evaluate()

        #expect(try context.fetch(FetchDescriptor<NudgeLog>()).isEmpty)
    }

    @Test func evaluateIfStaleSkipsRecentRun() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let person = Person(displayNameCache: "Anna", tier: .close)
        context.insert(person)
        context.insert(Interaction(person: person, date: .now.addingTimeInterval(-30 * 86_400), channel: .call))
        context.insert(NudgeRun(date: .now.addingTimeInterval(-3_600), selectedCount: 0))
        try context.save()

        let engine = makeEngine(container)
        await engine.evaluateIfStale()

        #expect(try context.fetch(FetchDescriptor<NudgeRun>()).count == 1, "no new run within 7 days")
    }

    @Test func expiredNudgesAreQuietlyClosed() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let person = Person(displayNameCache: "Old", tier: .paused)
        context.insert(person)
        let staleLog = NudgeLog(personID: person.id, date: .now.addingTimeInterval(-10 * 86_400), score: 1.0, reason: "old")
        context.insert(staleLog)
        try context.save()

        let engine = makeEngine(container)
        await engine.evaluate()

        let logs = try context.fetch(FetchDescriptor<NudgeLog>())
        #expect(logs.first { $0.id == staleLog.id }?.outcome == .expired)
    }
}
