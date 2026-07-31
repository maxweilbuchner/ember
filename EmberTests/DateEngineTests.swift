// DateEngineTests.swift

import Foundation
import SwiftData
import Testing
@testable import Ember

/// End-to-end coverage of the occasion notification pipeline (issues #2/#3):
/// what gets scheduled, with which copy, at which local time, and how the edge
/// cases behave — after-9:00 catch-up, precedence, Feb 29, year wrap, DST,
/// dedup, and custom dates at full birthday parity.
@MainActor
@Suite("Date engine")
struct DateEngineTests {
    private let calendar = fixedCalendar()

    private struct Rig {
        var container: ModelContainer
        var spy: SchedulerSpy
        var engine: DateEngine
    }

    private func makeRig(
        contacts: StubContacts = StubContacts(),
        calendar: Calendar? = nil
    ) throws -> Rig {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let spy = SchedulerSpy()
        let engine = DateEngine(
            container: container,
            contacts: contacts,
            scheduler: spy,
            calendar: calendar ?? self.calendar
        )
        return Rig(container: container, spy: spy, engine: engine)
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int,
        hour: Int = 12, minute: Int = 0,
        calendar: Calendar? = nil
    ) -> Date {
        (calendar ?? self.calendar).date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        )!
    }

    @discardableResult
    private func person(
        _ name: String,
        tier: CadenceTier = .close,
        isPartner: Bool = false,
        contactID: String? = nil,
        birthday: DateComponents? = nil,
        in container: ModelContainer
    ) throws -> Person {
        let person = Person(
            contactID: contactID,
            displayNameCache: name,
            tier: tier,
            isPartnerMode: isPartner,
            manualBirthday: birthday
        )
        container.mainContext.insert(person)
        try container.mainContext.save()
        return person
    }

    // MARK: Happy path

    @Test func dayOfAtNineLocalPlusHeadsUpThreeDaysBefore() async throws {
        let rig = try makeRig()
        try person("Anna", birthday: DateComponents(month: 6, day: 15), in: rig.container)

        await rig.engine.refresh(now: date(2026, 6, 10))

        let specs = await rig.spy.added
        #expect(specs.count == 2)

        let dayOf = try #require(specs.first { $0.identifier.hasSuffix("-day") })
        #expect(dayOf.title == NudgeCopy.birthdayDayOfTitle(name: "Anna"))
        #expect(dayOf.body == NudgeCopy.birthdayDayOfBody())
        #expect(dayOf.identifier.contains("2026-06-15"))
        #expect(dayOf.fireDateComponents?.day == 15)
        #expect(dayOf.fireDateComponents?.hour == 9)
        #expect(dayOf.fireDateComponents?.timeZone == calendar.timeZone)

        let headsUp = try #require(specs.first { $0.identifier.hasSuffix("-headsup") })
        #expect(headsUp.title == NudgeCopy.birthdayHeadsUpTitle(name: "Anna"))
        #expect(headsUp.fireDateComponents?.day == 12)
        #expect(headsUp.fireDateComponents?.hour == 9)
    }

    @Test func noHeadsUpWhenBirthdayWithinThreeDays() async throws {
        let rig = try makeRig()
        try person("Anna", birthday: DateComponents(month: 6, day: 12), in: rig.container)

        await rig.engine.refresh(now: date(2026, 6, 10))

        let specs = await rig.spy.added
        #expect(specs.count == 1)
        #expect(specs.first?.identifier.hasSuffix("-day") == true)
    }

    @Test func windowBoundarySevenInEightOut() async throws {
        let rig = try makeRig()
        try person("Seven", birthday: DateComponents(month: 6, day: 17), in: rig.container)
        try person("Eight", birthday: DateComponents(month: 6, day: 18), in: rig.container)

        await rig.engine.refresh(now: date(2026, 6, 10))

        let titles = await rig.spy.added.map(\.title)
        #expect(titles.contains(NudgeCopy.birthdayDayOfTitle(name: "Seven")))
        #expect(!titles.contains(NudgeCopy.birthdayDayOfTitle(name: "Eight")))
    }

    // MARK: Dedup & sweeping

    @Test func refreshTwiceLeavesOneRequestPerOccasion() async throws {
        let rig = try makeRig()
        try person("Anna", birthday: DateComponents(month: 6, day: 15), in: rig.container)

        await rig.engine.refresh(now: date(2026, 6, 10))
        await rig.engine.refresh(now: date(2026, 6, 10, hour: 13))

        let pending = await rig.spy.pending
        #expect(pending.count == 2, "sweep must replace, not accumulate: \(pending)")
        #expect(Set(pending).count == pending.count)
    }

    @Test func staleForeignRequestsAreSweptOurPrefixOnly() async throws {
        let rig = try makeRig()
        await rig.spy.seedPending(["birthday-stale-old-day", "nudge-someone-123"])

        await rig.engine.refresh(now: date(2026, 6, 10))

        let removed = await rig.spy.removedPending
        #expect(removed == ["birthday-stale-old-day"], "only birthday- requests are ours to sweep")
    }

    // MARK: After-9:00 catch-up (the dropped-notification bug)

    @Test func dayOfAfterNineFiresImmediately() async throws {
        let rig = try makeRig()
        try person("Anna", birthday: DateComponents(month: 6, day: 15), in: rig.container)

        await rig.engine.refresh(now: date(2026, 6, 15, hour: 15))

        let specs = await rig.spy.added
        #expect(specs.count == 1)
        #expect(specs.first?.fireDateComponents == nil, "past 9:00 on the day → deliver immediately")
        #expect(specs.first?.identifier.hasSuffix("-day") == true)
    }

    @Test func immediateCatchUpIsNotRepeatedOnSecondRefreshSameDay() async throws {
        let rig = try makeRig()
        try person("Anna", birthday: DateComponents(month: 6, day: 15), in: rig.container)

        await rig.engine.refresh(now: date(2026, 6, 15, hour: 15))
        await rig.engine.refresh(now: date(2026, 6, 15, hour: 18))

        let immediate = await rig.spy.added.filter { $0.fireDateComponents == nil }
        #expect(immediate.count == 1, "DateAlertRecord must dedup same-day re-foregrounds")
    }

    @Test func headsUpNeverFiresLate() async throws {
        let rig = try makeRig()
        // Birthday in 5 days, but it's already 10:00 — the heads-up moment for a
        // *different* (3-days-out) date hasn't passed; craft one that has:
        // birthday in 3 days, refresh at 10:00 → heads-up fire time (9:00 today) has passed.
        try person("Anna", birthday: DateComponents(month: 6, day: 18), in: rig.container)

        await rig.engine.refresh(now: date(2026, 6, 15, hour: 10))

        let specs = await rig.spy.added
        #expect(specs.count == 1, "only the future day-of; no late heads-up")
        #expect(specs.first?.identifier.hasSuffix("-day") == true)
    }

    @Test func nothingFiresTheDayAfter() async throws {
        let rig = try makeRig()
        try person("Anna", birthday: DateComponents(month: 6, day: 15), in: rig.container)

        await rig.engine.refresh(now: date(2026, 6, 16))

        #expect(await rig.spy.added.isEmpty)
    }

    // MARK: Precedence (canonical: contact-first)

    @Test func linkedContactBirthdayBeatsManual() async throws {
        let contacts = StubContacts(contactsByID: [
            "c1": .fixture(id: "c1", name: "Anna", birthday: DateComponents(month: 6, day: 15))
        ])
        let rig = try makeRig(contacts: contacts)
        try person("Anna", contactID: "c1", birthday: DateComponents(month: 6, day: 20), in: rig.container)

        await rig.engine.refresh(now: date(2026, 6, 10))

        let dayOf = try #require(await rig.spy.added.first { $0.identifier.hasSuffix("-day") })
        #expect(dayOf.identifier.contains("2026-06-15"), "the contact's birthday wins for linked people")
    }

    @Test func linkedWithoutContactBirthdayFallsBackToManual() async throws {
        let contacts = StubContacts(contactsByID: [
            "c1": .fixture(id: "c1", name: "Anna", birthday: nil)
        ])
        let rig = try makeRig(contacts: contacts)
        try person("Anna", contactID: "c1", birthday: DateComponents(month: 6, day: 15), in: rig.container)

        await rig.engine.refresh(now: date(2026, 6, 10))

        #expect(await rig.spy.added.count == 2)
    }

    @Test func unresolvableContactFallsBackToManual() async throws {
        let rig = try makeRig() // empty stub: contactID resolves to nothing
        try person("Anna", contactID: "gone", birthday: DateComponents(month: 6, day: 15), in: rig.container)

        await rig.engine.refresh(now: date(2026, 6, 10))

        #expect(await rig.spy.added.count == 2, "unresolvable contactID is a normal state, not an error")
    }

    @Test func noBirthdayAnywhereSchedulesNothing() async throws {
        let rig = try makeRig()
        try person("Anna", in: rig.container)

        await rig.engine.refresh(now: date(2026, 6, 10))

        #expect(await rig.spy.added.isEmpty)
    }

    // MARK: Eligibility at the scheduling level

    @Test func orbitExcludedPausedPartnerIncluded() async throws {
        let rig = try makeRig()
        let birthday = DateComponents(month: 6, day: 15)
        try person("Orbit", tier: .orbit, birthday: birthday, in: rig.container)
        try person("Partner", tier: .paused, isPartner: true, birthday: birthday, in: rig.container)

        await rig.engine.refresh(now: date(2026, 6, 10))

        let titles = await rig.spy.added.map(\.title)
        #expect(titles.contains(NudgeCopy.birthdayDayOfTitle(name: "Partner")))
        #expect(!titles.contains(NudgeCopy.birthdayDayOfTitle(name: "Orbit")))
    }

    // MARK: Calendar edge cases

    @Test func feb29SchedulesMarchFirstInNonLeapYear() async throws {
        let rig = try makeRig()
        try person("Leap", birthday: DateComponents(month: 2, day: 29), in: rig.container)

        await rig.engine.refresh(now: date(2027, 2, 26))

        let dayOf = try #require(await rig.spy.added.first { $0.identifier.hasSuffix("-day") })
        #expect(dayOf.identifier.contains("2027-03-01"))
    }

    @Test func feb29SchedulesFeb29InLeapYear() async throws {
        let rig = try makeRig()
        try person("Leap", birthday: DateComponents(month: 2, day: 29), in: rig.container)

        await rig.engine.refresh(now: date(2028, 2, 26))

        let dayOf = try #require(await rig.spy.added.first { $0.identifier.hasSuffix("-day") })
        #expect(dayOf.identifier.contains("2028-02-29"))
    }

    @Test func yearWrapUsesLocalDayStampNotUTC() async throws {
        // Auckland is UTC+13 around New Year: local Jan 1 is Dec 31 in UTC, so an
        // ISO-8601 (UTC) stamp would name the wrong day. The stamp must be local.
        let auckland = fixedCalendar("Pacific/Auckland")
        let rig = try makeRig(calendar: auckland)
        try person("NewYear", birthday: DateComponents(month: 1, day: 1), in: rig.container)

        await rig.engine.refresh(now: date(2026, 12, 30, calendar: auckland))

        let dayOf = try #require(await rig.spy.added.first { $0.identifier.hasSuffix("-day") })
        #expect(dayOf.identifier.contains("2027-01-01"), "got \(dayOf.identifier)")
    }

    @Test func springForwardTransitionStillSchedulesNineLocal() async throws {
        // Europe/Berlin DST begins Mar 29 2026 (02:00 → 03:00); 9:00 still exists
        // and both notifications must stay at 9:00 local across the transition.
        let rig = try makeRig()
        try person("DST", birthday: DateComponents(month: 3, day: 29), in: rig.container)

        await rig.engine.refresh(now: date(2026, 3, 25))

        let specs = await rig.spy.added
        #expect(specs.count == 2)
        for spec in specs {
            #expect(spec.fireDateComponents?.hour == 9)
            #expect(spec.fireDateComponents?.timeZone == calendar.timeZone)
        }
    }

    // MARK: Upcoming (Today tab feed)

    @Test func upcomingSortsAscendingAndHonoursWindow() async throws {
        let rig = try makeRig()
        try person("Later", birthday: DateComponents(month: 6, day: 16), in: rig.container)
        try person("Sooner", birthday: DateComponents(month: 6, day: 11), in: rig.container)
        try person("Outside", birthday: DateComponents(month: 7, day: 1), in: rig.container)

        let upcoming = await rig.engine.upcoming(withinDays: 7, now: date(2026, 6, 10))

        #expect(upcoming.map(\.displayName) == ["Sooner", "Later"])
        #expect(upcoming.map(\.daysAway) == [1, 6])
    }

    // MARK: Custom dates (issue #3 — full birthday parity)

    @discardableResult
    private func customDate(
        _ label: String,
        month: Int, day: Int,
        for person: Person,
        in container: ModelContainer
    ) throws -> CustomDate {
        let customDate = CustomDate(person: person, label: label, month: month, day: day)
        container.mainContext.insert(customDate)
        try container.mainContext.save()
        return customDate
    }

    @Test func customDateSchedulesDayOfAndHeadsUp() async throws {
        let rig = try makeRig()
        let anna = try person("Anna", in: rig.container)
        try customDate("Anniversary", month: 6, day: 15, for: anna, in: rig.container)

        await rig.engine.refresh(now: date(2026, 6, 10))

        let specs = await rig.spy.added
        #expect(specs.count == 2)
        let dayOf = try #require(specs.first { $0.identifier.hasSuffix("-day") })
        #expect(dayOf.identifier.hasPrefix("date-"))
        #expect(dayOf.title == NudgeCopy.customDateDayOfTitle(name: "Anna", label: "Anniversary"))
        #expect(dayOf.fireDateComponents?.hour == 9)
        let headsUp = try #require(specs.first { $0.identifier.hasSuffix("-headsup") })
        #expect(headsUp.title == NudgeCopy.customDateHeadsUpTitle(name: "Anna", label: "Anniversary"))
    }

    @Test func customDateHonoursTierEligibility() async throws {
        let rig = try makeRig()
        let orbit = try person("Orbit", tier: .orbit, in: rig.container)
        try customDate("Anniversary", month: 6, day: 15, for: orbit, in: rig.container)

        await rig.engine.refresh(now: date(2026, 6, 10))

        #expect(await rig.spy.added.isEmpty)
    }

    @Test func birthdayAndCustomDateSameDayProduceDistinctRequests() async throws {
        let rig = try makeRig()
        let anna = try person("Anna", birthday: DateComponents(month: 6, day: 15), in: rig.container)
        try customDate("Anniversary", month: 6, day: 15, for: anna, in: rig.container)

        await rig.engine.refresh(now: date(2026, 6, 14))

        let identifiers = await rig.spy.added.map(\.identifier)
        #expect(identifiers.count == 2, "one day-of each, no heads-up at 1 day out")
        #expect(Set(identifiers).count == 2)
        #expect(identifiers.contains { $0.hasPrefix("birthday-") })
        #expect(identifiers.contains { $0.hasPrefix("date-") })
    }

    @Test func customDateCatchUpDedupsLikeBirthdays() async throws {
        let rig = try makeRig()
        let anna = try person("Anna", in: rig.container)
        try customDate("Anniversary", month: 6, day: 15, for: anna, in: rig.container)

        await rig.engine.refresh(now: date(2026, 6, 15, hour: 15))
        await rig.engine.refresh(now: date(2026, 6, 15, hour: 18))

        let immediate = await rig.spy.added.filter { $0.fireDateComponents == nil }
        #expect(immediate.count == 1)
    }

    @Test func staleCustomRequestsAreSwept() async throws {
        let rig = try makeRig()
        await rig.spy.seedPending(["date-old-2026-01-01-day", "birthday-old-2026-01-01-day", "nudge-x"])

        await rig.engine.refresh(now: date(2026, 6, 10))

        let removed = await rig.spy.removedPending
        #expect(removed.sorted() == ["birthday-old-2026-01-01-day", "date-old-2026-01-01-day"])
    }

    @Test func upcomingMergesBirthdaysAndCustomDatesSorted() async throws {
        let rig = try makeRig()
        let anna = try person("Anna", birthday: DateComponents(month: 6, day: 16), in: rig.container)
        try customDate("Anniversary", month: 6, day: 12, for: anna, in: rig.container)

        let upcoming = await rig.engine.upcoming(withinDays: 7, now: date(2026, 6, 10))

        #expect(upcoming.count == 2)
        #expect(upcoming.first?.kind == .custom(label: "Anniversary"))
        #expect(upcoming.first?.daysAway == 2)
        #expect(upcoming.last?.kind == .birthday)
    }

    @Test func customFeb29NormalisesLikeBirthdays() async throws {
        let rig = try makeRig()
        let anna = try person("Anna", in: rig.container)
        try customDate("Anniversary", month: 2, day: 29, for: anna, in: rig.container)

        await rig.engine.refresh(now: date(2027, 2, 26))

        let dayOf = try #require(await rig.spy.added.first { $0.identifier.hasSuffix("-day") })
        #expect(dayOf.identifier.contains("2027-03-01"))
    }
}
