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
            case .customDateSoon(let label, let daysAway):
                let inline = lowercasedFirst(label)
                switch daysAway {
                case 0: lines.append(String(localized: "It's their \(inline) today."))
                case 1: lines.append(String(localized: "Their \(inline) is tomorrow."))
                default: lines.append(String(localized: "Their \(inline) is in \(daysAway) days."))
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
            case .customDateSoon(let label, let daysAway):
                let inline = lowercasedFirst(label)
                parts.append(daysAway == 0
                    ? String(localized: "\(inline) today")
                    : String(localized: "\(inline) in \(daysAway) days"))
            case .openCommitments:
                parts.append(String(localized: "open commitment"))
            }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Occasion notifications (DateEngine)

    static func birthdayDayOfTitle(name: String) -> String {
        String(localized: "\(name)'s birthday is today 🎂")
    }

    static func birthdayDayOfBody() -> String {
        String(localized: "A lovely day to reach out.")
    }

    static func birthdayHeadsUpTitle(name: String) -> String {
        String(localized: "\(name)'s birthday is in 3 days")
    }

    static func birthdayHeadsUpBody() -> String {
        String(localized: "Time enough to plan something small.")
    }

    static func customDateDayOfTitle(name: String, label: String) -> String {
        String(localized: "It's \(name)'s \(lowercasedFirst(label)) today")
    }

    static func customDateHeadsUpTitle(name: String, label: String) -> String {
        String(localized: "\(name)'s \(lowercasedFirst(label)) is in 3 days")
    }

    /// User labels arrive title-cased ("Anniversary"); mid-sentence they read
    /// better lowercased. Leaves anything else (acronyms, names) alone.
    private static func lowercasedFirst(_ text: String) -> String {
        guard let first = text.first, first.isUppercase,
              text.dropFirst().allSatisfy({ !$0.isUppercase }) else { return text }
        return first.lowercased() + text.dropFirst()
    }

    /// Commitments are verb phrases typed after "You said you'd…", often
    /// sentence-cased ("Send Anna the book"). Lowercases only a plain
    /// capitalised first word, so names later on and acronyms ("CV") survive.
    private static func verbPhrase(_ text: String) -> String {
        let word = text.prefix { !$0.isWhitespace }
        guard let first = word.first, first.isUppercase, word.count > 1,
              word.dropFirst().allSatisfy({ !$0.isUppercase }),
              !word.hasPrefix("I'") else { return text }
        return first.lowercased() + text.dropFirst()
    }

    /// The context line under a nudge card's name — the "Last time she was
    /// interviewing at Bain" half of §4.4. An open commitment beats the last
    /// note (it's the more useful opener); nil when there's nothing to say.
    static func cardContext(lastInteractionNote: String?, firstOpenCommitment: String?) -> String? {
        if let commitment = firstOpenCommitment?.trimmingCharacters(in: .whitespacesAndNewlines), !commitment.isEmpty {
            return String(localized: "You said you'd \(clip(verbPhrase(commitment), limit: 60))")
        }
        if let note = lastInteractionNote?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            return String(localized: "Last time: \(clip(note, limit: 60))")
        }
        return nil
    }

    private static func clip(_ text: String, limit: Int = 80) -> String {
        NeutralPhrases.clip(text, limit: limit)
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

    /// "They appear in 2 journal entries." with automatic grammar agreement.
    /// The `^[…](inflect: true)` markup is only processed on the AttributedString
    /// localization path — `String(localized:)` hands it through verbatim — so
    /// this wrapper localizes as AttributedString and flattens.
    static func journalAppearances(count: Int) -> String {
        String(AttributedString(localized: "They appear in ^[\(count) journal entries](inflect: true).").characters)
    }

    /// Forward-looking occasion phrase for chips and lists: "today" / "tomorrow" /
    /// "in N days" — the one place a future count is allowed (spec §4.4).
    static func upcoming(daysAway: Int) -> String {
        switch daysAway {
        case 0: String(localized: "today")
        case 1: String(localized: "tomorrow")
        default: String(localized: "in \(daysAway) days")
        }
    }

    /// "Last: coffee, mid-June" — note if there is one, else the channel word.
    /// The note is clipped at a word so the date half always survives.
    static func lastContact(channel: Channel, note: String?, date: Date, now: Date = .now) -> String {
        let what = (note?.isEmpty == false ? note! : channel.title.lowercased())
        return String(localized: "Last: \(clip(what, limit: 30)), \(phrase(for: date, now: now))")
    }

    /// Shortens free text to `limit` characters, breaking at the last word
    /// boundary when one is reasonably close, so nothing ends mid-word.
    static func clip(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        var cut = String(trimmed.prefix(limit))
        if let lastSpace = cut.lastIndex(where: \.isWhitespace),
           cut.distance(from: cut.startIndex, to: lastSpace) >= limit / 2 {
            cut = String(cut[..<lastSpace])
        }
        // Drop a dangling "—" or "," left at the break, never the whole thing.
        while let last = cut.last, last.isWhitespace || last.isPunctuation, cut.count > 1 {
            cut.removeLast()
        }
        return cut + "…"
    }
}
