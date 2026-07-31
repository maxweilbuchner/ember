// NudgeEngineIntegrationTests.swift

import Foundation
import SwiftData
import Testing
@testable import Ember

/// Full evaluate() runs against an in-memory store — the engine wiring around
/// the pure scoring: cooldowns across runs, birthday inputs, the ≤3 cap.
@MainActor
@Suite("Nudge engine integration")
struct NudgeEngineIntegrationTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    private func makeEngine(
        _ container: ModelContainer,
        contacts: StubContacts = StubContacts(),
        scheduler: SchedulerSpy = SchedulerSpy()
    ) -> NudgeEngine {
        NudgeEngine(container: container, contacts: contacts, scheduler: scheduler)
    }

    private func overduePerson(_ name: String, in context: ModelContext) -> Person {
        let person = Person(displayNameCache: name, tier: .close)
        context.insert(person)
        context.insert(Interaction(person: person, date: .now.addingTimeInterval(-30 * 86_400), channel: .inPerson))
        return person
    }

    @Test func nudgedPersonIsNotRenudgedWithinCooldown() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = overduePerson("Anna", in: context)
        try context.save()

        let engine = makeEngine(container)
        await engine.evaluate()
        #expect(try context.fetch(FetchDescriptor<NudgeLog>()).count == 1)

        // A forced second run days later: still inside the 14-day cooldown.
        await engine.evaluate(now: .now.addingTimeInterval(8 * 86_400))
        let logs = try context.fetch(FetchDescriptor<NudgeLog>())
        #expect(logs.count == 1, "cooldown must hold across engine runs, got \(logs.count) logs")
    }

    @Test func snoozeSuppressesTheFollowingRun() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let person = overduePerson("Cathi", in: context)
        try context.save()

        let engine = makeEngine(container)
        await engine.evaluate()
        await engine.handleSnooze(personID: person.id, nudgeLogID: nil, now: .now.addingTimeInterval(2 * 86_400))

        // 15 days after the nudge, but only 13 after the snooze — still quiet.
        await engine.evaluate(now: .now.addingTimeInterval(15 * 86_400))
        let pending = try context.fetch(FetchDescriptor<NudgeLog>()).filter { $0.outcome == .pending }
        #expect(pending.isEmpty, "snooze grants a fresh 14-day window from the snooze itself")
    }

    @Test func manualBirthdayFeedsTheBonus() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let person = Person(displayNameCache: "Laura", tier: .close)
        // 8 days since contact (above the 7-day half-cadence gate) — only 0.57 recency,
        // so only the +2.0 birthday bonus can push them over the 1.0 threshold.
        context.insert(person)
        context.insert(Interaction(person: person, date: .now.addingTimeInterval(-8 * 86_400), channel: .message))
        let inThreeDays = Calendar.current.date(byAdding: .day, value: 3, to: .now)!
        person.manualBirthday = Calendar.current.dateComponents([.month, .day], from: inThreeDays)
        try context.save()

        let engine = makeEngine(container)
        await engine.evaluate()

        let logs = try context.fetch(FetchDescriptor<NudgeLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.reason.localizedCaseInsensitiveContains("birthday") == true)
    }

    @Test func engineUsesContactBirthdayWhenLinked() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let person = Person(contactID: "c1", displayNameCache: "Laura", tier: .close)
        context.insert(person)
        context.insert(Interaction(person: person, date: .now.addingTimeInterval(-8 * 86_400), channel: .message))
        try context.save()

        let inThreeDays = Calendar.current.date(byAdding: .day, value: 3, to: .now)!
        let contacts = StubContacts(contactsByID: [
            "c1": .fixture(id: "c1", name: "Laura", birthday: Calendar.current.dateComponents([.month, .day], from: inThreeDays))
        ])
        let engine = makeEngine(container, contacts: contacts)
        await engine.evaluate()

        let logs = try context.fetch(FetchDescriptor<NudgeLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.reason.localizedCaseInsensitiveContains("birthday") == true)
    }

    @Test func engineCapsAtThreeEvenWithFiveOverdue() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        for index in 0..<5 {
            _ = overduePerson("Person \(index)", in: context)
        }
        try context.save()

        let engine = makeEngine(container)
        await engine.evaluate()

        let logs = try context.fetch(FetchDescriptor<NudgeLog>())
        #expect(logs.count == 3)
        #expect(try context.fetch(FetchDescriptor<NudgeRun>()).first?.selectedCount == 3)
    }

    @Test func pausedAndPartnerNeverAppearEvenWhenMaximallyOverdue() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let paused = Person(displayNameCache: "Paused", tier: .paused)
        let partner = Person(displayNameCache: "Partner", tier: .close, isPartnerMode: true)
        context.insert(paused)
        context.insert(partner)
        for person in [paused, partner] {
            context.insert(Interaction(person: person, date: .now.addingTimeInterval(-500 * 86_400), channel: .call))
        }
        try context.save()

        let engine = makeEngine(container)
        await engine.evaluate()

        #expect(try context.fetch(FetchDescriptor<NudgeLog>()).isEmpty)
    }

    @Test func customDateFeedsTheBonus() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let person = Person(displayNameCache: "Laura", tier: .close)
        // 8 days since contact — only the +2.0 custom-date bonus clears the threshold.
        context.insert(person)
        context.insert(Interaction(person: person, date: .now.addingTimeInterval(-8 * 86_400), channel: .message))
        let inThreeDays = Calendar.current.date(byAdding: .day, value: 3, to: .now)!
        let components = Calendar.current.dateComponents([.month, .day], from: inThreeDays)
        context.insert(CustomDate(person: person, label: "Anniversary", month: components.month!, day: components.day!))
        try context.save()

        let engine = makeEngine(container)
        await engine.evaluate()

        let logs = try context.fetch(FetchDescriptor<NudgeLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.reason.localizedCaseInsensitiveContains("anniversary") == true)
    }

    @Test func dateEngineUpcomingRespectsTiersAndPartner() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        let birthday = Calendar.current.dateComponents([.month, .day], from: tomorrow)

        let close = Person(displayNameCache: "Close", tier: .close, manualBirthday: birthday)
        let orbit = Person(displayNameCache: "Orbit", tier: .orbit, manualBirthday: birthday)
        let pausedPartner = Person(displayNameCache: "Partner", tier: .paused, isPartnerMode: true, manualBirthday: birthday)
        context.insert(close)
        context.insert(orbit)
        context.insert(pausedPartner)
        try context.save()

        let dateEngine = DateEngine(container: container, contacts: StubContacts(), scheduler: SchedulerSpy())
        let upcoming = await dateEngine.upcoming(withinDays: 7)

        let names = Set(upcoming.map(\.displayName))
        #expect(names.contains("Close"))
        #expect(names.contains("Partner"), "partner gets birthdays even when paused")
        #expect(!names.contains("Orbit"), "orbit tier gets no birthday surfacing")
    }

    // MARK: The "Weekly nudges" switch (GH #10)

    private func setNudges(_ enabled: Bool, in container: ModelContainer) {
        NotificationSettings.update(in: container.mainContext) { $0.nudgesEnabled = enabled }
    }

    @Test func nudgesOffProducesNoLogsNoRunAndNoNotifications() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = overduePerson("Anna", in: context)
        try context.save()
        setNudges(false, in: container)

        let spy = SchedulerSpy()
        await makeEngine(container, scheduler: spy).evaluate()

        #expect(try context.fetch(FetchDescriptor<NudgeLog>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<NudgeRun>()).isEmpty, "no run row: the staleness clock must freeze")
        #expect(await spy.added.isEmpty)
    }

    @Test func pausingFreezesTheStalenessClock() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = overduePerson("Anna", in: context)
        try context.save()
        let engine = makeEngine(container)
        let t0 = Date.now

        await engine.evaluate(now: t0)
        #expect(try context.fetch(FetchDescriptor<NudgeRun>()).count == 1)

        setNudges(false, in: container)
        await engine.evaluate(now: t0.addingTimeInterval(10 * 86_400))
        #expect(try context.fetch(FetchDescriptor<NudgeRun>()).count == 1, "a paused engine records nothing")

        // Ten days of frozen clock means the first foreground after re-enabling
        // is already stale, so nudges resume immediately.
        setNudges(true, in: container)
        await engine.resumeNudges(now: t0.addingTimeInterval(10 * 86_400))
        #expect(try context.fetch(FetchDescriptor<NudgeRun>()).count == 2)
    }

    @Test func reEnablingWithinTheWeekStaysSilent() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = overduePerson("Anna", in: context)
        try context.save()
        let engine = makeEngine(container)
        let t0 = Date.now

        await engine.evaluate(now: t0)
        setNudges(false, in: container)
        setNudges(true, in: container)
        await engine.resumeNudges(now: t0.addingTimeInterval(2 * 86_400))

        #expect(try context.fetch(FetchDescriptor<NudgeRun>()).count == 1,
                "toggling off and on must not buy an extra run — that would blow the ≤3/week ceiling")
    }

    @Test func perPersonCooldownSurvivesAToggleCycle() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = overduePerson("Anna", in: context)
        try context.save()
        let engine = makeEngine(container)
        let t0 = Date.now

        await engine.evaluate(now: t0)
        setNudges(false, in: container)
        await engine.cancelScheduledNudges()
        setNudges(true, in: container)
        await engine.evaluate(now: t0.addingTimeInterval(10 * 86_400))

        #expect(try context.fetch(FetchDescriptor<NudgeLog>()).count == 1,
                "expiring a log must not reset its date, or re-enabling would re-blast the same people")
    }

    @Test func cancellingExpiresOpenLogsAndPullsTheirNotifications() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = overduePerson("Anna", in: context)
        try context.save()
        let spy = SchedulerSpy()
        let engine = makeEngine(container, scheduler: spy)

        await engine.evaluate()
        let notificationID = try #require(context.fetch(FetchDescriptor<NudgeLog>()).first?.notificationID)

        await engine.cancelScheduledNudges()

        let logs = try context.fetch(FetchDescriptor<NudgeLog>())
        #expect(logs.allSatisfy { $0.outcome == .expired })
        #expect(await spy.removedPending.contains(notificationID))
        #expect(await spy.removedDelivered.contains(notificationID))
        #expect(await spy.pending.isEmpty)
    }

    @Test func cancellingAlsoPullsNotificationsOfAlreadyExpiredLogs() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        // `evaluate` expires week-old pending logs without pulling their
        // notifications, so a `.pending`-only sweep would strand this banner.
        context.insert(NudgeLog(
            personID: UUID(),
            score: 2,
            reason: "It's been a while",
            outcome: .expired,
            notificationID: "nudge-stranded-123"
        ))
        try context.save()
        let spy = SchedulerSpy()

        await makeEngine(container, scheduler: spy).cancelScheduledNudges()

        #expect(await spy.removedPending == ["nudge-stranded-123"])
        #expect(await spy.removedDelivered == ["nudge-stranded-123"])
    }

    @Test func occasionAlertsOffDoesNotAffectNudgeEvaluation() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = overduePerson("Anna", in: context)
        try context.save()
        NotificationSettings.update(in: container.mainContext) { $0.occasionAlertsEnabled = false }

        await makeEngine(container).evaluate()

        #expect(try context.fetch(FetchDescriptor<NudgeLog>()).count == 1, "the two switches are independent")
    }
}
