<!-- EMBER_SPEC.md -->
# Ember — Product & Architecture Specification

**Purpose of this document:** Complete brief for building "Ember", a privacy-first iOS personal CRM, from scratch. Hand this to Claude Code as the project's source of truth. A v1 exists (SwiftUI/SwiftData, ~4.6k LOC, archived); this is a rewrite that ports its lessons, not its code. Where this spec says MUST/NEVER, treat it as a hard requirement.

---

## 1. Product

### 1.1 One-liner
An app that helps you be a better friend, partner, and family member — by remembering who matters, what you talked about, and when it's time to reach out, entirely on-device.

### 1.2 Core loop
1. **Capture** — user writes a short journal entry or logs an interaction ("coffee with Anna, she got the Bain offer") in under 30 seconds.
2. **Resolve** — on-device AI extracts people, commitments, and life events; user confirms with one tap.
3. **Nudge** — once a week, the app picks ≤3 people worth reaching out to and delivers a notification **with context and a drafted opener**, deep-linking into Messages.

### 1.3 Design principles (non-negotiable)
- **Outbound over tracking.** The product is the nudge-with-context, not the dashboard. Every feature must shorten the path from "I should text them" to a sent message.
- **Zero guilt mechanics.** NO streaks, NO scores, NO "relationship health %", NO red overdue badges, NO negative framing of elapsed time. Never display time-since-contact as a deficit. Max 3 nudges per week, tone of a friend's suggestion.
- **Privacy as architecture.** No backend, no accounts, no analytics SDKs, no network calls except OS services. All AI inference on-device (Apple Foundation Models). This is the marketing position AND the technical constraint.
- **Capture must be nearly free.** Cold start to typing < 1 second. No splash screen. Logging an interaction from a notification must not require opening the app.
- **The journal is one capture path, not the required habit.** Interactions can be logged directly without journaling.

### 1.4 Explicitly out of scope for v1
Gift ideas beyond a simple list, tags/groups, relationship graphs/maps, CSV import, CloudKit sync, iPad/macOS, Android, widgets beyond one lock-screen capture widget, localisation (English only), subscription infrastructure.

---

## 2. Platform & project setup

| Setting | Value |
|---|---|
| Language | Swift 6, strict concurrency ON from day one |
| UI | SwiftUI only, `@Observable` (no ObservableObject/Combine) |
| Persistence | SwiftData, local store only (`cloudKitDatabase: .none`) |
| Min deployment | iOS 26.0 (required for Foundation Models framework) |
| AI | Apple Foundation Models framework (on-device), no fallback path in v1 |
| Project name | `Ember` (align ALL bundle IDs, schemes, test targets — v1 had leftover "socialise" naming; do not repeat) |
| Bundle ID | `com.maw.ember` (NEW App Store Connect record — do not reuse the old com.maw.link record) |
| Dependencies | ZERO third-party packages. Apple frameworks only: SwiftUI, SwiftData, Contacts, UserNotifications, BackgroundTasks, FoundationModels, LocalAuthentication, AppIntents |
| Testing | Swift Testing (not XCTest) for unit tests; test the scoring engine and extraction post-processing exhaustively |

**Xcode project conventions:**
- Folder structure: `App/`, `Models/`, `Services/`, `Features/<FeatureName>/` (views + view logic co-located per feature), `Components/`, `Resources/`.
- Every file starts with a comment line containing the file name.
- Imports sorted logically at top of each file (Apple frameworks first, alphabetical).
- No file may exist in two folders (v1 had duplicated `LongPressButton.swift`, `NotificationAlert.swift` — do not repeat).

---

## 3. Data model (SwiftData)

All models local-only. Use `#Unique` / `#Index` macros. IDs are `UUID` — NEVER use `Date()` as an identity (v1 bug in `ContactIdea`).

### 3.1 `Person`
The app-owned representation of a human. **Does NOT duplicate Contacts data.**
```
@Model final class Person {
    #Unique<Person>([\.id])
    var id: UUID
    var contactID: String?          // CNContact.identifier; nil = unlinked person
    var displayNameCache: String    // refreshed from Contacts on sync; used when contact unresolvable
    var tier: CadenceTier           // .close, .regular, .orbit, .paused
    var isPartnerMode: Bool         // see §6.4 — excluded from recency scoring
    var manualBirthday: DateComponents?  // only if not linked to a contact
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Interaction.person) var interactions: [Interaction]
    @Relationship(deleteRule: .cascade, inverse: \Commitment.person)  var commitments: [Commitment]
    @Relationship(deleteRule: .cascade, inverse: \Idea.person)        var ideas: [Idea]
    @Relationship(inverse: \Entry.mentions)                           var mentions: [Entry]
}
enum CadenceTier: Int, Codable { case close = 0, regular, orbit, paused }
// Target cadence (days): close 14, regular 45, orbit 120, paused = never nudged
```
**Contacts strategy:** store `contactID` reference only. Resolve name/photo/birthday/phone live via `CNContactStore` through `ContactService` (in-memory cache, invalidated on `CNContactStoreDidChange`). Handle unresolvable IDs gracefully: Person survives contact deletion/merge as "unlinked", journal history intact, UI offers re-link. Do NOT request `CNContactNoteKey` (requires special entitlement — never needed).

### 3.2 `Entry` (journal)
```
@Model final class Entry {
    #Unique<Entry>([\.id]); #Index<Entry>([\.date])
    var id: UUID
    var date: Date                  // timestamped; MULTIPLE entries per day allowed
    var text: String
    var imageFilenames: [String]    // native array — NOT JSON-in-a-string (v1 workaround, obsolete).
                                    // Filenames only, resolved against Application Support at runtime
                                    // (absolute paths break on container UUID change)
    var extractionState: ExtractionState  // .pending, .reviewed, .skipped
    @Relationship var mentions: [Person]
}
```

### 3.3 `Interaction` — **the core new entity**
"I actually communicated with this person." Distinct from a journal mention (v1's single biggest modelling gap: mentions were the only recency signal).
```
@Model final class Interaction {
    #Unique<Interaction>([\.id]); #Index<Interaction>([\.date])
    var id: UUID
    var person: Person?
    var date: Date
    var dateIsApproximate: Bool     // supports "saw Cathi last week"
    var channel: Channel            // .inPerson, .call, .message, .other
    var note: String?
    var sourceEntryID: UUID?        // set when auto-created from a journal mention
}
```
Creation paths: (a) auto-suggested when an entry mentions a person ("Did you see/talk to them? → creates Interaction"), (b) direct 2-tap logging from Person screen, (c) "We spoke" action button directly on a nudge notification, (d) retroactive with approximate date.

### 3.4 `Commitment`
"You said you'd send Daniel that book." Extracted by AI or added manually. Fields: `id: UUID`, `person: Person?`, `text: String`, `dueHint: Date?`, `isDone: Bool`, `createdAt: Date`, `sourceEntryID: UUID?`. Open commitments boost nudge score and appear in nudge context.

### 3.5 `Idea`
Simple per-person list (gift ideas, topics to raise). Fields: `id: UUID`, `person: Person?`, `text: String`, `isDone: Bool`, `createdAt: Date`. Identity/equality by `id` only.

### 3.6 `NudgeLog`
Audit of every nudge decision — needed for cooldowns and for honest "why am I seeing this?" UI. Fields: `id: UUID`, `personID: UUID`, `date: Date`, `score: Double`, `reason: String`, `outcome: NudgeOutcome` (.pending, .actedOn, .snoozed, .dismissed, .expired).

### 3.7 Explicitly deleted from v1
- `dailyStreak`, `interactionsPerDay`, `UserStats`, `ValueCard` — guilt gamification, banned by §1.3.
- The default `Link.xcdatamodeld` (`Item`/timestamp template) from v1 — dead file; do not port.
- `LabeledPhoneNumber` model — phone numbers now resolved live from Contacts.
- `promptText`/`defaultTitle` journal-prompt machinery — v2 entries have no titles; first line is the preview.

---

## 4. Services layer

Actors, dependency-injected via SwiftUI environment. **NO singletons** (v1's `static var shared` on a struct holding `@Query`/`@Environment` was the root cause of its notification engine silently never working — property wrappers only resolve inside the View update cycle). Each service receives the shared `ModelContainer` and creates its own `ModelContext`.

### 4.1 `ContactService` (actor)
- Permission flow (`CNContactStore.requestAccess`), including the iOS limited-access picker.
- Live resolution `contactID → (name, photo, birthday, phoneNumbers)` with in-memory cache.
- Observes `CNContactStoreDidChange`; refreshes cache and `displayNameCache`.
- Name search for the extraction resolver (given/family/nickname, case- and diacritic-insensitive — support "Julia", "Dani", "Max W").
- Modern async/await only — no completion handlers, no `DispatchQueue.global` wrapping (v1 mixed three concurrency paradigms here).

### 4.2 `ExtractionService` (actor)
Wraps Foundation Models. Runs on entry save, always producing **suggestions, never silent writes**.
- Input: entry text + candidate name list from ContactService.
- Output (use `@Generable` guided generation): mentioned people (with confidence), implied interactions (person + channel guess), commitments, notable life events (free text, attached to the Interaction note).
- Session per extraction; keep prompts short; handle `unavailable` states (device not eligible, model downloading) by falling back to manual mention selection — the sheet UX from v1's `ContactSelectorView` is proven, port its behaviour.
- Post-processing (pure functions, heavily unit-tested): map extracted names → Person via ContactService search; ambiguous → ask; unknown name → offer "create unlinked Person".
- v1 note: inline `@`-mention autocomplete was attempted and abandoned (SwiftUI TextEditor has no cursor API). Do NOT attempt it. Natural writing + post-hoc extraction replaces it entirely.

### 4.3 `DraftService` (actor)
Foundation Models generation of the message opener for a nudge. Input: person's display name, last 1–2 interaction notes, open commitments, days elapsed, upcoming birthday. Output: 1–2 sentence casual opener in the user's language register. MUST degrade gracefully: if model unavailable, nudge ships without a draft (context only). Never auto-send; drafts are editable and inserted via share/Messages composer.

### 4.4 `NudgeEngine` (actor) — the heart of the app
- Registered `BGAppRefreshTask` (identifier `com.maw.ember.nudge.refresh`), requested weekly; also re-evaluated on app foreground if >7 days since last run (BGTask is best-effort).
- Scoring per non-paused, non-partner Person:
  `score = daysSinceLastInteraction / tierCadenceDays` (recency pressure, capped at 3.0)
  `+ 2.0 if birthday within 7 days`
  `+ 0.5 per open Commitment (max +1.5)`
  `− ∞ if nudged within last 14 days (cooldown via NudgeLog)`
  `− ∞ if interaction within last (tierCadenceDays / 2)`
- Select top ≤3 with score ≥ 1.0. Fewer qualify → send fewer. Zero → send nothing. Silence is fine.
- For each selected: build context string, request draft from DraftService, schedule `UNNotificationRequest` with category `NUDGE` and actions: **"We spoke"** (logs Interaction, no app open), **"Snooze 2 weeks"**, default tap → deep link to Compose screen.
- Notification copy tone: "Anna — it's been a while. Last time she was interviewing at Bain. Ask how it went." NEVER "You haven't spoken to Anna in 94 days."
- Birthday notifications: separate daily-morning check, only for `.close`/`.regular` tiers and partner, on the day + optional 3-day heads-up.
- All scheduling state lives in SwiftData (`NudgeLog` + scheduled-notification IDs), NOT in UserDefaults (v1 split state across both and they desynced).

### 4.5 `SecurityService`
FaceID/passcode app lock via LocalAuthentication (port v1 `LockedView` behaviour). Blur content in app switcher.

### 4.6 `ExportService`
Full JSON export (all entities) + images as a zip to Files; and a destructive "Delete everything" with confirmation. Required for trust and App Store review posture.

---

## 5. App structure & UX

### 5.1 Navigation
Three tabs. NO splash screen (v1 had a hardcoded 2s delay — banned).
1. **Today** (default): capture field focused at top ("What happened?"), below it: pending extraction confirmations, today's nudges, upcoming birthdays. This tab is the app.
2. **People**: list grouped by tier; Person detail = timeline of interactions & mentions, commitments, ideas, cadence control. Time since last contact shown neutrally ("Last: coffee, mid-June") — never as a warning.
3. **Journal**: reverse-chron entries, search, calendar jump.
Settings behind a gear on People: contact sync, notification prefs, security, export/delete, about.

### 5.2 Key flows
- **Capture:** type → save → extraction chips appear inline ("Mentioned: Julia ✓ Anna ✓ | Interaction? | Commitment: 'send book' +") → one tap each to confirm. Skippable; entry saves regardless. `extractionState` tracks review.
- **Compose (from nudge):** context card (last notes, commitments, birthday) + editable AI draft + one button into Messages with the person's number. After the Messages sheet closes, ask "Sent? → log Interaction (.message)".
- **Onboarding (target < 2 min):** value promise → Contacts permission (with limited-access path) → "pick your people": search/select contacts, drag into tiers, optionally mark one person as partner → notification permission → done. No account, ever.
- **Interaction quick-log:** from Person screen: channel picker + optional note + date (default now, allow approximate past) = 2 taps minimum.

### 5.3 Empty states
Port the spirit of v1's `QuietSurfer`: calm, encouraging, instructive. Never "0 friends contacted".

### 5.4 Visual identity & app icon
- **Icon concept: the botanical flame** — a single flame whose inner shape reads as a leaf/sprout (or a sprout whose silhouette reads as a flame). One mark, two readings: warmth you keep alive + something you tend and grow. Flat, single glyph, no gradients-heavy realism; must read at 29 pt.
- **Palette:** warm ember tones (amber/terracotta) against a deep neutral (charcoal/ink) or warm off-white. No clinical blues, no productivity-app neon.
- **Type & UI tone:** rounded, humanist (SF Rounded acceptable for display), generous whitespace, calm motion. The interface should feel like a well-kept notebook, not a dashboard.
- **Name: Ember** (decided). The mark is a flame whose inner core reads as a leaf/sprout — flame-forward ordering of the botanical-flame concept. Working tagline: "Ember — keep the people you love warm."
- App Store listing name will likely need a suffix for search disambiguation (e.g. "Ember — thoughtful check-ins"); the crowded "Ember" namespace (mug hardware, JS framework) is a known, accepted trade-off. Trademark check (EUIPO/USPTO Class 9/42) still pending — flagged as a pre-TestFlight task, not a blocker for development.

---

## 6. Decisions already made (do not reopen)

1. **Rewrite, not refactor** — v1 code is reference only; port the schema *ideas* and `ContactSelectorView`/`LockedView` behaviour, nothing wholesale.
2. **iOS 26 minimum, no non-AI fallback build** — extraction has a manual fallback UI, but the app requires Foundation Models eligibility. Accepted trade-off for a v1 with zero API costs.
3. **Local-only, no CloudKit in v1** — but write the schema CloudKit-compatibly anyway (all relationships optional or with defaults, no unique constraints CloudKit can't honour) so migration is possible. `.none` cloudKitDatabase now.
4. **Partner mode (§3.1 `isPartnerMode`)** — partner is excluded from recency scoring entirely (nudging you to "check in" with someone you live with is absurd); partner still gets birthday, commitments, and ideas surfaced.
5. **Multiple timestamped entries per day** — v1's one-page-per-day model fights capture-anywhere.
6. **Monetisation: one-time purchase** — no subscription code paths, no paywall in v1 builds.
7. **English only at launch** — but hardcode zero user-facing strings; use String Catalogs from the start.

---

## 7. Build order (suggested milestones)

1. **M1 — Skeleton:** project setup per §2, all SwiftData models + migrations plan, tab shell, capture → save entry working.
2. **M2 — People:** ContactService with live resolution, onboarding + tier picker, Person list/detail, manual interaction logging, unlinked-person handling.
3. **M3 — Nudge engine:** scoring (unit-tested against fixture scenarios), BGTask registration, notifications with actions, NudgeLog, birthday pipeline. *This is the product; do it before AI.*
4. **M4 — AI:** ExtractionService + confirmation chips, DraftService + Compose flow, availability handling.
5. **M5 — Trust & polish:** FaceID lock, export/delete, empty states, app icon, TestFlight.

Test priorities: NudgeEngine scoring (pure, exhaustive), extraction post-processing name resolution, contact-deletion/merge edge cases, notification action handlers.

---

## 8. Known traps (from v1's corpse — avoid)

- SwiftUI property wrappers (`@Query`, `@Environment`) outside a View are silently dead. Services never use them.
- `UNCalendarNotificationTrigger(repeats: true)` per-contact was the v1 design; it never shipped and doesn't fit the batch-scoring model. Don't resurrect it.
- Absolute file paths in the store break across reinstalls. Filenames + runtime resolution only.
- UserDefaults for schedule state desyncs from the store. SwiftData is the single source of truth for anything the NudgeEngine reads.
- Duplicate contact entries and merges WILL happen in real address books — treat `contactID` resolution failure as a normal state, not an error.
- Do not build `@`-mention autocomplete. It was tried. TextEditor can't do it. Extraction replaces it.
