// NudgeScoring.swift

import Foundation

/// The scoring heart of the nudge engine. Pure functions only — no SwiftData,
/// no clocks, no I/O — so it can be tested exhaustively against fixtures.
///
/// score = daysSinceLastInteraction / tierCadenceDays   (capped at 3.0)
///       + 2.0 if birthday within 7 days
///       + 0.5 per open commitment (max +1.5)
/// Disqualified entirely (nil) when paused, partner, nudged/snoozed within
/// 14 days, or interacted within tierCadenceDays / 2.
nonisolated enum NudgeScoring {
    static let recencyCap = 3.0
    static let birthdayWindowDays = 7
    static let birthdayBonus = 2.0
    /// Full birthday parity for custom dates (issue #3); a birthday and a custom
    /// date in the same window stack — the ≤3 selection cap still bounds output.
    static let customDateBonus = 2.0
    static let commitmentBonus = 0.5
    static let commitmentBonusCap = 1.5
    static let nudgeCooldownDays = 14.0
    static let scoreThreshold = 1.0
    static let maxNudges = 3

    static func score(_ input: ScoringInput) -> Double? {
        guard !input.isPartner, let cadence = input.tier.cadenceDays else { return nil }
        let cadenceDays = Double(cadence)
        if let sinceNudge = input.daysSinceLastNudgeEvent, sinceNudge < nudgeCooldownDays {
            return nil
        }
        if let sinceInteraction = input.daysSinceLastInteraction, sinceInteraction < cadenceDays / 2 {
            return nil
        }
        let recencyDays = input.daysSinceLastInteraction ?? input.daysSinceCreated
        var score = min(recencyDays / cadenceDays, recencyCap)
        if let birthday = input.daysUntilBirthday, (0...birthdayWindowDays).contains(birthday) {
            score += birthdayBonus
        }
        if let customDate = input.daysUntilCustomDate, (0...birthdayWindowDays).contains(customDate) {
            score += customDateBonus
        }
        score += min(Double(input.openCommitmentCount) * commitmentBonus, commitmentBonusCap)
        return score
    }

    /// Top ≤3 with score ≥ 1.0. Fewer qualify → fewer nudges. Zero → silence, which is fine.
    /// Deterministic: score descending, then personID ascending as tie-break.
    static func select(_ inputs: [ScoringInput]) -> [NudgeCandidate] {
        let qualified = inputs.compactMap { input -> NudgeCandidate? in
            guard let score = score(input), score >= scoreThreshold else { return nil }
            return NudgeCandidate(input: input, score: score, reasons: reasons(for: input))
        }
        let sorted = qualified.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.input.personID.uuidString < $1.input.personID.uuidString
        }
        return Array(sorted.prefix(maxNudges))
    }

    private static func reasons(for input: ScoringInput) -> [NudgeReason] {
        var reasons: [NudgeReason] = [.beenAWhile]
        if let birthday = input.daysUntilBirthday, (0...birthdayWindowDays).contains(birthday) {
            reasons.append(.birthdaySoon(daysAway: birthday))
        }
        if let customDate = input.daysUntilCustomDate, (0...birthdayWindowDays).contains(customDate),
           let label = input.customDateLabel {
            reasons.append(.customDateSoon(label: label, daysAway: customDate))
        }
        if input.openCommitmentCount > 0 {
            reasons.append(.openCommitments(input.openCommitmentTexts))
        }
        return reasons
    }
}

/// Canonical birthday precedence (spec §3.1): a linked contact's birthday wins;
/// the manual fields only fill in when no contact birthday exists. Every reader
/// (engines, Compose, profile) goes through here so the sources can't drift.
nonisolated enum BirthdayResolution {
    static func effectiveBirthday(contact: DateComponents?, manual: DateComponents?) -> DateComponents? {
        contact ?? manual
    }
}

/// Pure birthday date math shared by the nudge and birthday engines.
nonisolated enum BirthdayMath {
    /// Days from `now` (start of day) until the next occurrence of the birthday's
    /// month/day; 0 = today. Feb 29 normalises to Mar 1 in non-leap years.
    static func daysUntilNextBirthday(_ birthday: DateComponents, from now: Date, calendar: Calendar = .current) -> Int? {
        guard let month = birthday.month, let day = birthday.day else { return nil }
        let today = calendar.startOfDay(for: now)
        let year = calendar.component(.year, from: today)
        for candidateYear in [year, year + 1] {
            var components = DateComponents()
            components.year = candidateYear
            components.month = month
            components.day = day
            if let date = calendar.date(from: components), date >= today {
                return calendar.dateComponents([.day], from: today, to: date).day
            }
        }
        return nil
    }

    /// Valid day-of-month range for the editor wheels. Without a year, February
    /// allows 29 so Feb-29 birthdays stay enterable.
    static func validDayRange(month: Int, year: Int?, calendar: Calendar = .current) -> ClosedRange<Int> {
        var components = DateComponents()
        components.year = year ?? 2000 // leap reference year when no year is chosen
        components.month = month
        guard let date = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            return 1...31
        }
        return 1...(range.upperBound - 1)
    }
}
