// NudgeCopy.swift

import Foundation

/// The single place nudge copy is written. Tone rule (spec §1.3, §4.4):
/// a friend's suggestion with context — NEVER a day-count, deficit, or guilt framing.
nonisolated enum NudgeCopy {
    static func notificationTitle(for candidate: NudgeCandidate) -> String {
        candidate.input.displayName
    }

    static func notificationBody(for candidate: NudgeCandidate) -> String {
        var lines: [String] = []
        for reason in candidate.reasons {
            switch reason {
            case .beenAWhile:
                if let note = candidate.input.lastInteractionNote, !note.isEmpty {
                    lines.append(String(localized: "It's been a while. Last time: \(clip(note))"))
                } else {
                    lines.append(String(localized: "It's been a while — could be a nice moment to say hi."))
                }
            case .birthdaySoon(let daysAway):
                switch daysAway {
                case 0: lines.append(String(localized: "Their birthday is today 🎂"))
                case 1: lines.append(String(localized: "Their birthday is tomorrow 🎂"))
                default: lines.append(String(localized: "Their birthday is in \(daysAway) days."))
                }
            case .openCommitments(let texts):
                if let first = texts.first {
                    lines.append(String(localized: "You mentioned you'd \(clip(first, limit: 60))"))
                }
            }
        }
        return lines.joined(separator: " ")
    }

    /// Context plus an optional sanitized AI draft. A nil draft is a normal state —
    /// the nudge simply ships context-only.
    static func notificationBody(for candidate: NudgeCandidate, draft: String?) -> String {
        let context = notificationBody(for: candidate)
        guard let draft, !draft.isEmpty else { return context }
        return context + "\n“" + draft + "”"
    }

    /// Short reason stored on NudgeLog and shown in the "why am I seeing this?" UI.
    static func reasonLine(for candidate: NudgeCandidate) -> String {
        var parts: [String] = [String(localized: "It's been a while")]
        for reason in candidate.reasons {
            switch reason {
            case .beenAWhile:
                break
            case .birthdaySoon(let daysAway):
                parts.append(daysAway == 0
                    ? String(localized: "birthday today")
                    : String(localized: "birthday in \(daysAway) days"))
            case .openCommitments:
                parts.append(String(localized: "open commitment"))
            }
        }
        return parts.joined(separator: " · ")
    }

    private static func clip(_ text: String, limit: Int = 80) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// Neutral time phrasing for the People UI: "mid-June", never "94 days ago".
nonisolated enum NeutralPhrases {
    static func phrase(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfDate = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: startOfDate, to: startOfToday).day ?? 0

        if days <= 0 { return String(localized: "today") }
        if days == 1 { return String(localized: "yesterday") }
        if days < 7 { return String(localized: "this week") }
        if days < 14 { return String(localized: "last week") }

        let day = calendar.component(.day, from: date)
        let month = date.formatted(.dateTime.month(.wide))
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let monthPart = sameYear ? month : "\(month) \(date.formatted(.dateTime.year()))"
        switch day {
        case ...10: return String(localized: "early \(monthPart)")
        case ...20: return String(localized: "mid-\(monthPart)")
        default: return String(localized: "late \(monthPart)")
        }
    }

    /// "Last: coffee, mid-June" — note if there is one, else the channel word.
    static func lastContact(channel: Channel, note: String?, date: Date, now: Date = .now) -> String {
        let what = (note?.isEmpty == false ? note! : channel.title.lowercased())
        let shortWhat = what.count > 30 ? String(what.prefix(30)) + "…" : what
        return String(localized: "Last: \(shortWhat), \(phrase(for: date, now: now))")
    }
}
