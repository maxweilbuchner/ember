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

/// Adds `NotificationSettings` (GH #10). No existing model type changed, so
/// SchemaV1 still hashes to what's already on disk and the stage is a pure
/// add-table.
///
/// Note the model types are shared between versions rather than copied per
/// version — fine for a `.lightweight` stage, but a future *custom* stage will
/// need version-scoped copies of whatever it transforms.
nonisolated enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Person.self, Entry.self, Interaction.self, Commitment.self, Idea.self,
            CustomDate.self, NudgeLog.self, NudgeRun.self, DateAlertRecord.self,
            NotificationSettings.self,
        ]
    }
}

/// One place to bump, so the app and the tests can't drift apart.
typealias CurrentSchema = SchemaV2

nonisolated enum EmberMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]
    }
}
