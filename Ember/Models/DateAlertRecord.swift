// DateAlertRecord.swift

import Foundation
import SwiftData

/// Records an immediately-delivered occasion notification (day-of catch-up after
/// 9:00) so foregrounding again on the same day doesn't re-alert. Future-dated
/// requests need no record — their deterministic identifiers dedup via the
/// pending-request sweep. Engine state, not user data: never exported.
@Model
nonisolated final class DateAlertRecord {
    #Unique<DateAlertRecord>([\.id])

    var id: UUID = UUID()
    /// The deterministic notification identifier that was delivered.
    var identifier: String = ""
    var sentAt: Date = Date.now

    init(identifier: String, sentAt: Date = .now) {
        self.id = UUID()
        self.identifier = identifier
        self.sentAt = sentAt
    }
}
