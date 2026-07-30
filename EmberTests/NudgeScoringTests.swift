// NudgeScoringTests.swift

import Foundation
import Testing
@testable import Ember

@Suite("NudgeScoring")
struct NudgeScoringTests {
    private func input(
        personID: UUID = UUID(),
        tier: CadenceTier = .close,
        isPartner: Bool = false,
        daysSinceLastInteraction: Double? = nil,
        daysSinceCreated: Double = 100,
        daysUntilBirthday: Int? = nil,
        daysUntilCustomDate: Int? = nil,
        customDateLabel: String? = nil,
        openCommitmentCount: Int = 0,
        daysSinceLastNudgeEvent: Double? = nil
    ) -> ScoringInput {
        ScoringInput(
            personID: personID,
            displayName: "Test",
            tier: tier,
            isPartner: isPartner,
            daysSinceLastInteraction: daysSinceLastInteraction,
            daysSinceCreated: daysSinceCreated,
            daysUntilBirthday: daysUntilBirthday,
            daysUntilCustomDate: daysUntilCustomDate,
            customDateLabel: customDateLabel,
            openCommitmentCount: openCommitmentCount,
            daysSinceLastNudgeEvent: daysSinceLastNudgeEvent
        )
    }

    // MARK: Base recency

    @Test func recencyIsDaysOverCadence() {
        let score = NudgeScoring.score(input(tier: .close, daysSinceLastInteraction: 28))
        #expect(score == 2.0) // 28 / 14
    }

    @Test func recencyRespectsTierCadences() {
        #expect(NudgeScoring.score(input(tier: .regular, daysSinceLastInteraction: 45)) == 1.0)
        #expect(NudgeScoring.score(input(tier: .orbit, daysSinceLastInteraction: 120)) == 1.0)
    }

    @Test func recencyIsCappedAtThree() {
        let score = NudgeScoring.score(input(tier: .close, daysSinceLastInteraction: 1000))
        #expect(score == 3.0)
    }

    @Test func neverInteractedFallsBackToCreationDate() {
        let score = NudgeScoring.score(input(tier: .close, daysSinceLastInteraction: nil, daysSinceCreated: 28))
        #expect(score == 2.0)
    }

    // MARK: Bonuses

    @Test func birthdayWithinSevenDaysAddsTwo() {
        for days in [0, 3, 7] {
            let score = NudgeScoring.score(input(tier: .close, daysSinceLastInteraction: 14, daysUntilBirthday: days))
            #expect(score == 3.0, "birthday in \(days) days should add 2.0")
        }
    }

    @Test func birthdayOutsideWindowAddsNothing() {
        let score = NudgeScoring.score(input(tier: .close, daysSinceLastInteraction: 14, daysUntilBirthday: 8))
        #expect(score == 1.0)
    }

    @Test func customDateWithinWindowAddsTwo() {
        let score = NudgeScoring.score(input(
            tier: .close, daysSinceLastInteraction: 14,
            daysUntilCustomDate: 3, customDateLabel: "Anniversary"
        ))
        #expect(score == 3.0)
    }

    @Test func customDateOutsideWindowAddsNothing() {
        let score = NudgeScoring.score(input(
            tier: .close, daysSinceLastInteraction: 14,
            daysUntilCustomDate: 8, customDateLabel: "Anniversary"
        ))
        #expect(score == 1.0)
    }

    @Test func birthdayAndCustomDateBonusesStack() {
        // Documented decision: both in the window → +4.0; the ≤3 selection cap
        // still bounds how many nudges ship.
        let score = NudgeScoring.score(input(
            tier: .close, daysSinceLastInteraction: 14,
            daysUntilBirthday: 2, daysUntilCustomDate: 3, customDateLabel: "Anniversary"
        ))
        #expect(score == 5.0)
    }

    @Test func customDateReasonCarriesLabel() {
        let candidate = NudgeScoring.select([
            input(
                tier: .close, daysSinceLastInteraction: 28,
                daysUntilCustomDate: 2, customDateLabel: "Anniversary"
            )
        ]).first
        #expect(candidate?.reasons.contains(.customDateSoon(label: "Anniversary", daysAway: 2)) == true)
    }

    @Test func commitmentsAddHalfEachCappedAtOneAndAHalf() {
        #expect(NudgeScoring.score(input(daysSinceLastInteraction: 14, openCommitmentCount: 1)) == 1.5)
        #expect(NudgeScoring.score(input(daysSinceLastInteraction: 14, openCommitmentCount: 2)) == 2.0)
        #expect(NudgeScoring.score(input(daysSinceLastInteraction: 14, openCommitmentCount: 3)) == 2.5)
        #expect(NudgeScoring.score(input(daysSinceLastInteraction: 14, openCommitmentCount: 5)) == 2.5) // capped
    }

    // MARK: Disqualifiers

    @Test func pausedTierIsNeverScored() {
        #expect(NudgeScoring.score(input(tier: .paused, daysSinceLastInteraction: 1000)) == nil)
    }

    @Test func partnerIsNeverScored() {
        #expect(NudgeScoring.score(input(isPartner: true, daysSinceLastInteraction: 1000, daysUntilBirthday: 0)) == nil)
    }

    @Test func nudgeCooldownFourteenDays() {
        #expect(NudgeScoring.score(input(daysSinceLastInteraction: 100, daysSinceLastNudgeEvent: 13.9)) == nil)
        #expect(NudgeScoring.score(input(daysSinceLastInteraction: 100, daysSinceLastNudgeEvent: 14.0)) != nil)
    }

    @Test func recentInteractionWithinHalfCadenceDisqualifies() {
        // close cadence 14 → half is 7
        #expect(NudgeScoring.score(input(tier: .close, daysSinceLastInteraction: 6.9)) == nil)
        #expect(NudgeScoring.score(input(tier: .close, daysSinceLastInteraction: 7.0)) != nil)
    }

    @Test func birthdayDoesNotOverrideCooldowns() {
        #expect(NudgeScoring.score(input(daysSinceLastInteraction: 1, daysUntilBirthday: 0)) == nil)
        #expect(NudgeScoring.score(input(daysSinceLastInteraction: 100, daysUntilBirthday: 0, daysSinceLastNudgeEvent: 2)) == nil)
    }

    // MARK: Selection

    @Test func thresholdBoundary() {
        // 13.9 days on close tier ≈ 0.993 — below threshold
        let below = input(tier: .close, daysSinceLastInteraction: 13.9)
        let at = input(tier: .close, daysSinceLastInteraction: 14.0)
        #expect(NudgeScoring.select([below]).isEmpty)
        #expect(NudgeScoring.select([at]).count == 1)
    }

    @Test func selectsAtMostThree() {
        let inputs = (0..<5).map { _ in input(tier: .close, daysSinceLastInteraction: 28) }
        #expect(NudgeScoring.select(inputs).count == 3)
    }

    @Test func fewerQualifyingMeansFewerNudges() {
        for count in 0...3 {
            let inputs = (0..<count).map { _ in input(tier: .close, daysSinceLastInteraction: 28) }
            #expect(NudgeScoring.select(inputs).count == count)
        }
    }

    @Test func zeroQualifiersMeansSilence() {
        let inputs = [
            input(tier: .paused, daysSinceLastInteraction: 500),
            input(tier: .close, daysSinceLastInteraction: 2),
        ]
        #expect(NudgeScoring.select(inputs).isEmpty)
    }

    @Test func selectionOrdersByScoreDescending() {
        let low = input(tier: .close, daysSinceLastInteraction: 14)   // 1.0
        let high = input(tier: .close, daysSinceLastInteraction: 42)  // 3.0
        let selected = NudgeScoring.select([low, high])
        #expect(selected.first?.score == 3.0)
        #expect(selected.last?.score == 1.0)
    }

    @Test func selectionIsDeterministicOnTies() {
        let a = input(personID: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000000")!, tier: .close, daysSinceLastInteraction: 28)
        let b = input(personID: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000000")!, tier: .close, daysSinceLastInteraction: 28)
        let firstOrder = NudgeScoring.select([a, b]).map(\.input.personID)
        let secondOrder = NudgeScoring.select([b, a]).map(\.input.personID)
        #expect(firstOrder == secondOrder)
        #expect(firstOrder.first == a.personID)
    }

    // MARK: Reasons

    @Test func reasonsIncludeBirthdayAndCommitments() {
        let candidate = NudgeScoring.select([
            input(
                tier: .close,
                daysSinceLastInteraction: 28,
                daysUntilBirthday: 2,
                openCommitmentCount: 1
            )
        ]).first
        #expect(candidate?.reasons.contains(.birthdaySoon(daysAway: 2)) == true)
        #expect(candidate?.reasons.contains(.beenAWhile) == true)
    }
}

@Suite("BirthdayMath")
struct BirthdayMathTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test func birthdayTodayIsZero() {
        let days = BirthdayMath.daysUntilNextBirthday(
            DateComponents(month: 6, day: 15),
            from: date(2026, 6, 15),
            calendar: calendar
        )
        #expect(days == 0)
    }

    @Test func birthdayTomorrowIsOne() {
        let days = BirthdayMath.daysUntilNextBirthday(
            DateComponents(month: 6, day: 16),
            from: date(2026, 6, 15),
            calendar: calendar
        )
        #expect(days == 1)
    }

    @Test func birthdayWrapsToNextYear() {
        let days = BirthdayMath.daysUntilNextBirthday(
            DateComponents(month: 1, day: 1),
            from: date(2026, 12, 31),
            calendar: calendar
        )
        #expect(days == 1)
    }

    @Test func missingComponentsGiveNil() {
        #expect(BirthdayMath.daysUntilNextBirthday(DateComponents(), from: .now, calendar: calendar) == nil)
        #expect(BirthdayMath.daysUntilNextBirthday(DateComponents(month: 3), from: .now, calendar: calendar) == nil)
    }

    @Test func february29NormalisesInNonLeapYears() {
        // 2027 is not a leap year: Feb 29 → Mar 1
        let days = BirthdayMath.daysUntilNextBirthday(
            DateComponents(month: 2, day: 29),
            from: date(2027, 2, 27),
            calendar: calendar
        )
        #expect(days == 2)
    }

    @Test func february29StaysFeb29InLeapYears() {
        let days = BirthdayMath.daysUntilNextBirthday(
            DateComponents(month: 2, day: 29),
            from: date(2028, 2, 27),
            calendar: calendar
        )
        #expect(days == 2)
    }

    @Test func february29OnNormalisedDayIsZero() {
        // Non-leap year, today is Mar 1 — the normalised occurrence is today.
        let days = BirthdayMath.daysUntilNextBirthday(
            DateComponents(month: 2, day: 29),
            from: date(2027, 3, 1),
            calendar: calendar
        )
        #expect(days == 0)
    }

    @Test func timezoneShiftedCalendarCountsLocalDays() {
        // Same instant, two calendars: what is "June 14, 23:30" in Berlin is
        // already June 15 in Tokyo — daysAway must follow the calendar's locality.
        let berlin = Calendar.gregorian(timeZone: "Europe/Berlin")
        let tokyo = Calendar.gregorian(timeZone: "Asia/Tokyo")
        let instant = berlin.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 23, minute: 30))!
        let birthday = DateComponents(month: 6, day: 15)
        #expect(BirthdayMath.daysUntilNextBirthday(birthday, from: instant, calendar: berlin) == 1)
        #expect(BirthdayMath.daysUntilNextBirthday(birthday, from: instant, calendar: tokyo) == 0)
    }

    // MARK: Editor day ranges

    @Test func februaryWithoutYearAllowsDay29() {
        #expect(BirthdayMath.validDayRange(month: 2, year: nil, calendar: calendar) == 1...29)
    }

    @Test func februaryNonLeapYearCapsAt28() {
        #expect(BirthdayMath.validDayRange(month: 2, year: 2025, calendar: calendar) == 1...28)
        #expect(BirthdayMath.validDayRange(month: 2, year: 2028, calendar: calendar) == 1...29)
    }

    @Test func monthLengthsAreRespected() {
        #expect(BirthdayMath.validDayRange(month: 4, year: nil, calendar: calendar) == 1...30)
        #expect(BirthdayMath.validDayRange(month: 7, year: nil, calendar: calendar) == 1...31)
    }
}

extension Calendar {
    fileprivate static func gregorian(timeZone identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }
}

@Suite("Birthday resolution")
struct BirthdayResolutionTests {
    @Test func contactBirthdayWinsWhenBothExist() {
        let contact = DateComponents(month: 6, day: 15)
        let manual = DateComponents(month: 6, day: 20)
        #expect(BirthdayResolution.effectiveBirthday(contact: contact, manual: manual) == contact)
    }

    @Test func manualFillsInWhenContactHasNone() {
        let manual = DateComponents(month: 6, day: 20)
        #expect(BirthdayResolution.effectiveBirthday(contact: nil, manual: manual) == manual)
    }

    @Test func nothingGivesNil() {
        #expect(BirthdayResolution.effectiveBirthday(contact: nil, manual: nil) == nil)
    }
}
