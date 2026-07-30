// EmberSchema.swift

import Foundation
import SwiftData

/// Versioned schema for the local-only Ember store.
///
/// CloudKit-migration delta (spec §6.3): the store is `cloudKitDatabase: .none` today,
/// so `#Unique`/`#Index` macros are used freely. CloudKit honours NO unique constraints,
/// so a future sync-enabled SchemaV2 must drop `#Unique` (all uniques are on generated
/// UUIDs, so dropping them is safe) and keep every relationship optional/defaulted —
/// which they already are.
nonisolated enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Person.self, Entry.self, Interaction.self, Commitment.self, Idea.self,
            CustomDate.self, NudgeLog.self, NudgeRun.self, DateAlertRecord.self,
        ]
    }
}

nonisolated enum EmberMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
