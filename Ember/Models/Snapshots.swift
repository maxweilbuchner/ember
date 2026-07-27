// Snapshots.swift

import Foundation

/// Sendable value types that cross actor boundaries in place of @Model objects
/// (models never leave the actor that fetched them).

nonisolated struct ScoringInput: Sendable, Hashable {
    var personID: UUID
    var displayName: String
    var tier: CadenceTier
    var isPartner: Bool
    /// Days since the most recent Interaction; nil = never logged one.
    var daysSinceLastInteraction: Double?
    /// Days since the Person record was created — recency proxy when no interaction exists.
    var daysSinceCreated: Double
    /// Days until the next birthday occurrence (0 = today); nil = unknown.
    var daysUntilBirthday: Int?
    var openCommitmentCount: Int
    /// Days since the last nudge *or* snooze event for this person; nil = never nudged.
    var daysSinceLastNudgeEvent: Double?
    /// Note text of the most recent interaction, for nudge context copy.
    var lastInteractionNote: String?
    /// Channel of the most recent interaction, for nudge context copy.
    var lastInteractionChannel: Channel?
    /// Up to a few open commitment texts, for nudge context copy.
    var openCommitmentTexts: [String] = []
}

nonisolated struct NudgeCandidate: Sendable, Hashable {
    var input: ScoringInput
    var score: Double
    var reasons: [NudgeReason]
}

nonisolated enum NudgeReason: Sendable, Hashable {
    case beenAWhile
    case birthdaySoon(daysAway: Int)
    case openCommitments([String])
}

/// Resolution result for one contactID, produced by ContactService for PersonSyncService.
nonisolated struct ContactResolution: Sendable, Hashable {
    var contactID: String
    /// nil = the store definitively has no contact with this identifier.
    var displayName: String?
}
