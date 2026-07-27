// NudgeLog.swift

import Foundation
import SwiftData

/// Audit of every nudge decision — powers cooldowns and the honest
/// "why am I seeing this?" UI. References the person by UUID (not a relationship)
/// so the audit trail survives person deletion.
@Model
nonisolated final class NudgeLog {
    #Unique<NudgeLog>([\.id])
    #Index<NudgeLog>([\.date])

    var id: UUID = UUID()
    var personID: UUID = UUID()
    var date: Date = Date.now
    var score: Double = 0
    var reason: String = ""
    var outcome: NudgeOutcome = NudgeOutcome.pending
    /// Identifier of the scheduled UNNotificationRequest, when one was sent.
    /// Lives in SwiftData, never UserDefaults (spec §4.4/§8).
    var notificationID: String?

    init(personID: UUID, date: Date = .now, score: Double, reason: String, outcome: NudgeOutcome = .pending, notificationID: String? = nil) {
        self.id = UUID()
        self.personID = personID
        self.date = date
        self.score = score
        self.reason = reason
        self.outcome = outcome
        self.notificationID = notificationID
    }
}

nonisolated enum NudgeOutcome: Int, Codable, Sendable {
    case pending = 0
    case actedOn = 1
    case snoozed = 2
    case dismissed = 3
    case expired = 4
}

/// One row per NudgeEngine evaluation run — including runs that selected nobody
/// ("silence is fine" still needs a timestamp so the foreground fallback knows
/// the engine isn't stale). Scheduling state lives in SwiftData by spec.
@Model
nonisolated final class NudgeRun {
    #Unique<NudgeRun>([\.id])
    #Index<NudgeRun>([\.date])

    var id: UUID = UUID()
    var date: Date = Date.now
    var selectedCount: Int = 0

    init(date: Date = .now, selectedCount: Int) {
        self.id = UUID()
        self.date = date
        self.selectedCount = selectedCount
    }
}
