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
- Contacts is read-only except for birthday write-back (`Services/BirthdayWriteBack.swift`, `ContactWriting` seam), which is opt-in per user and clears Ember's manual copy on success. Never add a silent or background write path.
- Notification scheduling state lives in SwiftData (`NudgeLog.notificationID`, `NudgeRun`, `DateAlertRecord`) — never UserDefaults.
- Birthday reads go through `BirthdayResolution.effectiveBirthday` (contact-first; manual is the unlinked/missing fallback) — never inline the precedence.

## Milestone status

All milestones M1–M5 are built; the app is feature-complete per `EMBER_SPEC.md` §1.4.

- M4 notes: the app depends on Foundation Models only through the `ExtractionProviding`/`DraftProviding` seams in `Services/AIProviders.swift`; `@Generable` types are private to `ExtractionService`. Every AI draft passes `DraftSanitizer` (tone guard) before display. `MentionReviewSheet` remains the manual fallback for unavailable-model states. `LiveModelSmokeTests` exercises the real model and no-ops where Apple Intelligence is off.
- M5 notes: `SecurityService` (injectable authenticator; never bricks when no passcode is set), `PrivacyShield` on RootView, `ExportService` (zip via `NSFileCoordinator .forUploading`; delete uses fetch-and-delete because batch `delete(model:)` skips in-memory stores), `EmberCaptureWidget` app-extension target (third target in pbxproj — its embed phase needs the explicit PBXBuildFile entries, unlike synchronized sources). App icon is a programmatic draft: `Scripts/draw_icon.swift` renders it; re-run it and copy the PNG into the appiconset to iterate. TestFlight steps in `RELEASING.md` (needs the user's Apple ID).
- M6 notes (spec §7 M6): `DateEngine` (ex-`BirthdayEngine`) schedules birthday + custom-date notifications through the `NotificationScheduling` seam (`Services/NotificationScheduling.swift`); engines take `any ContactResolving` and an injectable `Calendar`, so `DateEngineTests` runs against `SchedulerSpy`/`StubContacts` (`EmberTests/TestDoubles.swift`) with pinned time zones. Relations resolve live via `RelationResolver` (pure) + the Settings "Your card" pick (`MeCard` in ContactService.swift); relation labels never touch `isPartnerMode`. Custom-date labels are never fed to AI drafts (DraftSanitizer digit ban).
- Mention writes (spec §7 M6.7): everything that turns a suggestion into data goes through `Services/MentionApplier.swift` — never inline in a view. Auto-tagging is limited to `.person` outcomes (existing people); `.contact`/`.unknown`/ambiguous must stay user-tapped so Ember never silently adds someone to People. `ExtractionState.pending` means "extraction hasn't successfully completed" and is retried on foreground; `.reviewed` is set once extraction resolves, even when it named nobody.
- Person removal (spec §7 M6.6): all merge/anonymize logic lives in `Services/PersonMerge.swift` — never inline reassignment. Views calling it must follow with `AppServices.personRemoved(_:mergedInto:)` (suggestion remap + nudge close + occasion resweep). `Person.isPlaceholder` rows are filtered from the people list, extraction candidates, and person pickers — check those filters when adding a new person-listing surface.
