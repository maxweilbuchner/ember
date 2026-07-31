// NotificationSettings.swift

import Foundation
import SwiftData

/// The two in-app notification switches (GH #10). Lives in SwiftData rather than
/// UserDefaults because the engines read it — spec §8: SwiftData is the single
/// source of truth for anything the NudgeEngine reads. (SecurityService's lock
/// flag takes the UserDefaults carve-out precisely because no engine sees it.)
///
/// Zero rows is the normal state and means "both on": only the main context ever
/// inserts, so the engines' own contexts can never race to create a second row.
@Model
nonisolated final class NotificationSettings {
    #Unique<NotificationSettings>([\.id])

    var id: UUID = UUID()
    var nudgesEnabled: Bool = true
    var occasionAlertsEnabled: Bool = true
    var updatedAt: Date = Date.now

    init(nudgesEnabled: Bool = true, occasionAlertsEnabled: Bool = true, updatedAt: Date = .now) {
        self.id = UUID()
        self.nudgesEnabled = nudgesEnabled
        self.occasionAlertsEnabled = occasionAlertsEnabled
        self.updatedAt = updatedAt
    }
}

/// Sendable snapshot — `@Model` objects never cross actor boundaries.
nonisolated struct NotificationFlags: Sendable, Hashable {
    var nudgesEnabled: Bool = true
    var occasionAlertsEnabled: Bool = true

    static let allEnabled = NotificationFlags()
}

extension NotificationSettings {
    /// Read-only, and deliberately never inserts: an absent row means both
    /// switches are on, so a store that has never seen the settings screen stays
    /// byte-identical to one from before this feature existed.
    nonisolated static func flags(in context: ModelContext) -> NotificationFlags {
        guard let row = newest(in: context) else { return .allEnabled }
        return NotificationFlags(
            nudgesEnabled: row.nudgesEnabled,
            occasionAlertsEnabled: row.occasionAlertsEnabled
        )
    }

    /// The only write path, and only from the main context. Creates the row on
    /// first use, prunes any duplicate that somehow appeared, and saves before
    /// returning — the engines read through fresh ModelContexts, which see only
    /// committed writes.
    nonisolated static func update(
        in context: ModelContext,
        now: Date = .now,
        _ mutate: (NotificationSettings) -> Void
    ) {
        let rows = sortedRows(in: context)
        let target = rows.first ?? {
            let created = NotificationSettings()
            context.insert(created)
            return created
        }()
        for duplicate in rows.dropFirst() {
            context.delete(duplicate)
        }
        mutate(target)
        target.updatedAt = now
        try? context.save()
    }

    private nonisolated static func newest(in context: ModelContext) -> NotificationSettings? {
        sortedRows(in: context).first
    }

    /// Newest write wins, so a duplicate row can never resurrect a stale value.
    private nonisolated static func sortedRows(in context: ModelContext) -> [NotificationSettings] {
        let descriptor = FetchDescriptor<NotificationSettings>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
