# Ember

Privacy-first iOS personal CRM. **`EMBER_SPEC.md` is the source of truth** — read it before changing product behaviour. Anything marked MUST/NEVER there is a hard requirement (no guilt mechanics, no backend, no third-party dependencies, on-device AI only).

## Build & test

`xcode-select` on this machine points at CommandLineTools, so prefix xcodebuild:

```bash
env DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -project Ember.xcodeproj -scheme Ember \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

env DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -project Ember.xcodeproj -scheme Ember \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

- Swift 6 language mode, strict concurrency, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- The pbxproj uses **synchronized file system groups**: a new `.swift` file under `Ember/` or `EmberTests/` joins its target automatically — never add per-file pbxproj entries.
- Tests are Swift Testing (`@Test`/`#expect`), hosted in the app.

## Architecture

- **Models/** — SwiftData `@Model` classes, all `nonisolated`, schema versioned in `EmberSchema.swift` (`SchemaV1`). Local-only store (`cloudKitDatabase: .none`). `#Unique` only on generated UUIDs (documented CloudKit-migration delta). `NudgeRun` exists so "last engine run" lives in SwiftData, not UserDefaults.
- **Services/** — actors receiving the shared `ModelContainer`, each creating its own `ModelContext` per operation. **No singletons. No `@Query`/`@Environment` outside views.** `@Model` objects never cross actor boundaries — use the Sendable DTOs in `Models/Snapshots.swift`.
- **Pure logic** (`NudgeScoring`, `BirthdayMath`, `NameMatcher`, `NudgeCopy`, `NeutralPhrases`) has no SwiftData/UI imports and is exhaustively unit-tested. Keep it that way.
- **Features/<Name>/** — views + view logic co-located. `Components/` for shared views.
- `AppServices` (`@Observable`, MainActor) is the DI container, injected via `.environment(...)`.

## Conventions

- Every file starts with `// FileName.swift`.
- Imports: Apple frameworks only, alphabetical.
- All user-facing strings via `String(localized:)` — String Catalog at `Ember/Resources/Localizable.xcstrings`.
- Nudge/notification copy goes through `NudgeCopy`; elapsed-time display through `NeutralPhrases`. Never show time-since-contact as a deficit or day-count.
- Never request `CNContactNoteKey`. Unresolvable contactIDs are a normal state (unlinked Person), not an error.
- Notification scheduling state lives in SwiftData (`NudgeLog.notificationID`, `NudgeRun`) — never UserDefaults.

## Milestone status

- M1 (skeleton) / M2 (people) / M3 (nudge engine): built.
- M4 (Foundation Models extraction + drafts + Compose): not started — `MentionReviewSheet` is the manual fallback that stays.
- M5 (FaceID lock, export, Icon Composer icon, lock-screen widget, TestFlight): not started. Settings shows "Coming soon" rows.
