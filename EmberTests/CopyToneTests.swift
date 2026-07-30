// CopyToneTests.swift

import Foundation
import Testing
@testable import Ember

/// Regression guards for the spec's hardest UX rule (§1.3/§4.4): elapsed time is
/// NEVER shown as a deficit — no day-counts, no "ago", no guilt framing.
@Suite("Nudge copy tone")
struct CopyToneTests {
    private func candidate(
        note: String? = nil,
        daysUntilBirthday: Int? = nil,
        customDate: (label: String, daysAway: Int)? = nil,
        commitments: [String] = []
    ) -> NudgeCandidate {
        let input = ScoringInput(
            personID: UUID(),
            displayName: "Anna",
            tier: .close,
            isPartner: false,
            daysSinceLastInteraction: 94, // the spec's own anti-example: "94 days"
            daysSinceCreated: 200,
            daysUntilBirthday: daysUntilBirthday,
            daysUntilCustomDate: customDate?.daysAway,
            customDateLabel: customDate?.label,
            openCommitmentCount: commitments.count,
            daysSinceLastNudgeEvent: nil,
            lastInteractionNote: note,
            lastInteractionChannel: .inPerson,
            openCommitmentTexts: commitments
        )
        var reasons: [NudgeReason] = [.beenAWhile]
        if let daysUntilBirthday { reasons.append(.birthdaySoon(daysAway: daysUntilBirthday)) }
        if let customDate { reasons.append(.customDateSoon(label: customDate.label, daysAway: customDate.daysAway)) }
        if !commitments.isEmpty { reasons.append(.openCommitments(commitments)) }
        return NudgeCandidate(input: input, score: 3.0, reasons: reasons)
    }

    @Test func plainNudgeBodyContainsNoNumbersOrAgo() {
        let body = NudgeCopy.notificationBody(for: candidate())
        let hasNumber = body.contains { $0.isNumber }
        #expect(!hasNumber, "elapsed time must never appear as a number: \(body)")
        #expect(!body.localizedCaseInsensitiveContains("ago"))
        #expect(!body.localizedCaseInsensitiveContains("overdue"))
        #expect(!body.localizedCaseInsensitiveContains("haven't"))
    }

    @Test func nudgeWithNoteQuotesContextNotElapsedTime() {
        let body = NudgeCopy.notificationBody(for: candidate(note: "she was interviewing at Bain"))
        #expect(body.contains("interviewing at Bain"))
        #expect(!body.contains("94"))
    }

    @Test func longNotesAreClipped() {
        let long = String(repeating: "context ", count: 40)
        let body = NudgeCopy.notificationBody(for: candidate(note: long))
        #expect(body.contains("…"))
        #expect(body.count < 200)
    }

    @Test func birthdayIsTheOnlyAllowedNumberAndPointsForward() {
        #expect(NudgeCopy.notificationBody(for: candidate(daysUntilBirthday: 0)).contains("today"))
        #expect(NudgeCopy.notificationBody(for: candidate(daysUntilBirthday: 1)).contains("tomorrow"))
        let inFive = NudgeCopy.notificationBody(for: candidate(daysUntilBirthday: 5))
        #expect(inFive.contains("in 5 days"), "future-facing birthday counts are allowed")
    }

    @Test func commitmentsAppearInBody() {
        let body = NudgeCopy.notificationBody(for: candidate(commitments: ["send Daniel that book"]))
        #expect(body.contains("send Daniel that book"))
    }

    @Test func customDateCopyIsForwardLookingAndCarriesTheLabel() {
        let today = NudgeCopy.notificationBody(for: candidate(customDate: ("Anniversary", 0)))
        #expect(today.contains("anniversary today"))
        let tomorrow = NudgeCopy.notificationBody(for: candidate(customDate: ("Anniversary", 1)))
        #expect(tomorrow.contains("tomorrow"))
        let inFour = NudgeCopy.notificationBody(for: candidate(customDate: ("Anniversary", 4)))
        #expect(inFour.contains("anniversary is in 4 days"))
        for body in [today, tomorrow, inFour] {
            #expect(!body.localizedCaseInsensitiveContains("ago"), "\(body)")
            #expect(!body.localizedCaseInsensitiveContains("overdue"), "\(body)")
            #expect(!body.localizedCaseInsensitiveContains("haven't"), "\(body)")
        }
    }

    @Test func customDateReasonLineNamesTheOccasion() {
        let reason = NudgeCopy.reasonLine(for: candidate(customDate: ("First met", 3)))
        #expect(reason.contains("first met in 3 days"))
    }

    @Test func customDateNotificationTitlesReadNaturally() {
        #expect(NudgeCopy.customDateDayOfTitle(name: "Anna", label: "Anniversary") == "It's Anna's anniversary today")
        #expect(NudgeCopy.customDateHeadsUpTitle(name: "Anna", label: "Anniversary") == "Anna's anniversary is in 3 days")
    }

    @Test func birthdayNotificationCopyIsForwardLookingAndGuiltFree() {
        let strings = [
            NudgeCopy.birthdayDayOfTitle(name: "Anna"),
            NudgeCopy.birthdayDayOfBody(),
            NudgeCopy.birthdayHeadsUpTitle(name: "Anna"),
            NudgeCopy.birthdayHeadsUpBody(),
        ]
        for string in strings {
            #expect(!string.localizedCaseInsensitiveContains("ago"), "\(string)")
            #expect(!string.localizedCaseInsensitiveContains("overdue"), "\(string)")
            #expect(!string.localizedCaseInsensitiveContains("haven't"), "\(string)")
        }
        // The only digit across all four is the forward-facing "in 3 days".
        let digitBearing = strings.filter { $0.contains { $0.isNumber } }
        #expect(digitBearing == [NudgeCopy.birthdayHeadsUpTitle(name: "Anna")])
        #expect(NudgeCopy.birthdayHeadsUpTitle(name: "Anna").contains("in 3 days"))
    }

    @Test func reasonLineIsCompactAndNumberFreeForRecency() {
        let reason = NudgeCopy.reasonLine(for: candidate())
        let hasNumber = reason.contains { $0.isNumber }
        #expect(!hasNumber, "\(reason)")
        #expect(!reason.isEmpty)
    }
}

@Suite("Neutral time phrasing")
struct NeutralPhrasesTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test func recentDatesUseWords() {
        let now = date(2026, 7, 27)
        #expect(NeutralPhrases.phrase(for: now, now: now, calendar: calendar) == "today")
        #expect(NeutralPhrases.phrase(for: date(2026, 7, 26), now: now, calendar: calendar) == "yesterday")
        #expect(NeutralPhrases.phrase(for: date(2026, 7, 22), now: now, calendar: calendar) == "this week")
        #expect(NeutralPhrases.phrase(for: date(2026, 7, 14), now: now, calendar: calendar) == "last week")
    }

    @Test func olderDatesUseMonthParts() {
        let now = date(2026, 7, 27)
        #expect(NeutralPhrases.phrase(for: date(2026, 6, 5), now: now, calendar: calendar).hasPrefix("early"))
        #expect(NeutralPhrases.phrase(for: date(2026, 6, 15), now: now, calendar: calendar).hasPrefix("mid-"))
        #expect(NeutralPhrases.phrase(for: date(2026, 6, 25), now: now, calendar: calendar).hasPrefix("late"))
    }

    @Test func lastContactPrefersNoteOverChannel() {
        let now = date(2026, 7, 27)
        let withNote = NeutralPhrases.lastContact(channel: .inPerson, note: "coffee", date: date(2026, 6, 15), now: now)
        #expect(withNote.contains("coffee"))
        let noNote = NeutralPhrases.lastContact(channel: .call, note: nil, date: date(2026, 6, 15), now: now)
        #expect(noNote.localizedCaseInsensitiveContains("call"))
    }

    @Test func journalAppearancesInflectSingularAndPlural() {
        // Guards the AttributedString localization path — String(localized:)
        // would leak the ^[…](inflect: true) markup verbatim into the UI.
        #expect(NeutralPhrases.journalAppearances(count: 1) == "They appear in 1 journal entry.")
        #expect(NeutralPhrases.journalAppearances(count: 2) == "They appear in 2 journal entries.")
    }

    @Test func phrasesNeverCountDaysBackwards() {
        let now = date(2026, 7, 27)
        for daysBack in [0, 1, 5, 12, 40, 200, 400] {
            let past = calendar.date(byAdding: .day, value: -daysBack, to: now)!
            let phrase = NeutralPhrases.phrase(for: past, now: now, calendar: calendar)
            #expect(!phrase.localizedCaseInsensitiveContains("ago"), "\(phrase)")
            #expect(!phrase.contains("\(daysBack) day"), "\(phrase)")
        }
    }
}
