// KeepInTouch.swift

import Foundation

/// The one user-facing "how do you keep in touch?" choice. Folds the two stored
/// fields — `Person.tier` and `Person.isPartnerMode` — into a single picker, so
/// cadence and partner are set in one place with one vocabulary everywhere
/// (onboarding, Add People, Person detail, the People list sections).
///
/// Storage stays as is (§3.1): picking `.partner` leaves the stored tier
/// untouched, so un-partnering someone restores the cadence they had before.
/// Writes go through `KeepInTouchAssignment`, which owns the one-partner rule.
nonisolated enum KeepInTouch: Hashable, CaseIterable, Sendable {
    case partner
    case close
    case regular
    case orbit
    case paused

    init(tier: CadenceTier, isPartner: Bool) {
        guard !isPartner else {
            self = .partner
            return
        }
        switch tier {
        case .close: self = .close
        case .regular: self = .regular
        case .orbit: self = .orbit
        case .paused: self = .paused
        }
    }

    /// The tier this choice stores; `nil` for `.partner`, which keeps the tier.
    var tier: CadenceTier? {
        switch self {
        case .partner: nil
        case .close: .close
        case .regular: .regular
        case .orbit: .orbit
        case .paused: .paused
        }
    }

    var isPartner: Bool { self == .partner }

    /// Offered while sorting freshly picked people: pausing someone you just
    /// chose makes no sense, so `.paused` lives on their page only.
    static let addingChoices: [KeepInTouch] = [.partner, .close, .regular, .orbit]

    var title: String {
        switch self {
        case .partner: String(localized: "Partner")
        case .close: CadenceTier.close.title
        case .regular: CadenceTier.regular.title
        case .orbit: CadenceTier.orbit.title
        case .paused: CadenceTier.paused.title
        }
    }

    var systemImage: String? {
        self == .partner ? "heart.fill" : nil
    }

    /// What the choice does, stated plainly — must match what NudgeEngine and
    /// DateEngine actually do with it.
    var explanation: String {
        switch self {
        case .partner:
            String(localized: "Your partner is never nudged about staying in touch — birthdays, dates, commitments, and ideas still show up. One person at a time.")
        case .close:
            String(localized: "A suggestion about every couple of weeks, plus birthday and date alerts.")
        case .regular:
            String(localized: "A suggestion about every month or two, plus birthday and date alerts.")
        case .orbit:
            String(localized: "A suggestion a few times a year. No birthday or date alerts.")
        case .paused:
            String(localized: "No suggestions or alerts. Everything you've noted stays here.")
        }
    }
}
