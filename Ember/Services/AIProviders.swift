// AIProviders.swift

import Foundation

/// Seams between the app and Foundation Models: everything downstream depends on
/// these protocols and plain value types, never on the framework — so the whole
/// pipeline runs (and tests) without a model, and unavailable states degrade to
/// the manual flows.

protocol ExtractionProviding: Sendable {
    /// nil = model unavailable or generation failed → fall back to manual review.
    func extract(entryText: String, candidateNames: [String]) async -> ExtractionResult?
}

protocol DraftProviding: Sendable {
    /// nil = no draft → the nudge ships with context only. Never an error state.
    func draft(for context: DraftContext) async -> String?
}

// MARK: Extraction output (framework-free)

nonisolated struct ExtractionResult: Sendable, Hashable {
    var people: [ExtractedPerson] = []
    var commitments: [ExtractedCommitment] = []
}

nonisolated struct ExtractedPerson: Sendable, Hashable {
    var name: String
    var interacted: Bool
    var channelGuess: Channel
    var lifeEvent: String?
}

nonisolated struct ExtractedCommitment: Sendable, Hashable {
    var text: String
    var personName: String?
}

// MARK: Draft input

nonisolated struct DraftContext: Sendable, Hashable {
    var displayName: String
    var lastInteractionNotes: [String] = []
    var openCommitments: [String] = []
    var daysUntilBirthday: Int?

    init(displayName: String, lastInteractionNotes: [String] = [], openCommitments: [String] = [], daysUntilBirthday: Int? = nil) {
        self.displayName = displayName
        self.lastInteractionNotes = lastInteractionNotes
        self.openCommitments = openCommitments
        self.daysUntilBirthday = daysUntilBirthday
    }

    init(from input: ScoringInput) {
        self.displayName = input.displayName
        self.lastInteractionNotes = input.lastInteractionNote.map { [$0] } ?? []
        self.openCommitments = input.openCommitmentTexts
        self.daysUntilBirthday = input.daysUntilBirthday.flatMap { $0 <= NudgeScoring.birthdayWindowDays ? $0 : nil }
    }
}

// MARK: Draft tone guard

/// AI drafts are the one place guilt copy could sneak past the NudgeCopy funnel,
/// so every generated draft is checked here. A rejected draft means the nudge
/// ships context-only — silence beats a guilt trip (spec §1.3).
nonisolated enum DraftSanitizer {
    private static let bannedPatterns: [String] = [
        #"\d+\s*(day|week|month|year)"#,
        #"\bago\b"#,
        #"so long"#,
        #"too long"#,
        #"been (a while|forever|ages)"#,
        #"haven't (talked|spoken|seen|heard)"#,
        #"long time"#,
        #"sorry (for|that) (not|the)"#,
    ]

    static func sanitize(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Models love wrapping messages in quotes — unwrap them.
        for (open, close) in [("\"", "\""), ("“", "”"), ("'", "'")] {
            if text.hasPrefix(open) && text.hasSuffix(close) && text.count > 2 {
                text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        guard !text.isEmpty, text.count <= 280 else { return nil }
        let lowered = text.lowercased()
        for pattern in bannedPatterns
        where lowered.range(of: pattern, options: .regularExpression) != nil {
            return nil
        }
        return text
    }
}
