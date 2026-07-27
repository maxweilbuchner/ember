# Releasing Ember (TestFlight prep)

Manual steps that need Maximilian's Apple ID — everything else is automated.

## One-time setup

1. **Signing team**: in Xcode → project → each target's Signing & Capabilities, pick your team (or add `DEVELOPMENT_TEAM = <TEAMID>;` to all three target configs in `project.pbxproj`). All targets use `CODE_SIGN_STYLE = Automatic`.
2. **App Store Connect**: create a **new** app record for bundle ID `com.maw.ember` (spec §2: do NOT reuse the old `com.maw.link` record). Listing name suggestion from the spec: "Ember — thoughtful check-ins" (bare "Ember" is a crowded namespace).
3. **Trademark check** (spec §5.4): EUIPO/USPTO Class 9/42 search for "Ember" — flagged pre-TestFlight, still pending.

## Every release

```bash
env DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -project Ember.xcodeproj -scheme Ember \
  -destination 'generic/platform=iOS' archive -archivePath build/Ember.xcarchive
env DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -exportArchive \
  -archivePath build/Ember.xcarchive -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist   # method: app-store-connect
```

Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in all three targets together.

## App privacy questionnaire (App Store Connect)

- Data collection: **none**. No accounts, no analytics, no network calls except OS services.
- Contacts access: on-device only, never transmitted (matches `NSContactsUsageDescription`).
- Encryption: standard iOS encryption only → `ITSAppUsesNonExemptEncryption = NO` already set.

## Icon polish (optional, recommended before public TestFlight)

The current icon is a programmatic draft (`Scripts/draw_icon.swift` renders it; output lives in
`Ember/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`). For iOS 26 layered
glass effects, rebuild the botanical-flame mark in **Icon Composer** and replace the
appiconset with the exported `.icon` file (set `ASSETCATALOG_COMPILER_APPICON_NAME`
accordingly). Keep the mark: flame silhouette whose inner negative space is a leaf/sprout,
amber→terracotta on warm charcoal.

## Review-posture checklist (from the spec)

- [x] Export + delete-everything shipped (§4.6)
- [x] No guilt mechanics anywhere (§1.3) — guarded by CopyToneTests
- [x] All permission strings honest and specific
- [x] Trademark check — searched 2026-07-27, see notes below
- [x] Screenshots — `Scripts/screenshots.sh` regenerates `Screenshots/` from seeded demo data (listing copy in `LISTING.md`; privacy/support page in `docs/index.html`)

## Trademark search notes (2026-07-27, TMview API + USPTO web records — not legal advice)

"EMBER" as a word mark is heavily occupied in Class 9/42 in both registries:

- **EUIPO (registered word marks):** Sony Interactive Entertainment "Ember" (012674198, cl. 9/28/41, game); Eelmets Patendibüroo OÜ "EMBER" (019185759, cl. 9/39/42, reg. Oct 2025); Silicon Labs "EMBER" (002516672, cl. 9, chips); Willow Laboratories "EMBER" (013537345, cl. 9/10/44, health); Sandbag Climate "Ember" (018269556, cl. 42/45). Plus at least one pending (019335510).
- **USPTO:** Tilde Inc. "EMBER" (88446133, cl. 9 — the Ember.js framework); Ember Technologies (mug company) holds EMBER marks but in medical-container/hardware goods, not personal-productivity apps; various EMBER-prefixed marks (TECH EMBER, EMBER INTERACTIVE, EMBERAI).

Assessment: no registration found for an identical mark covering a personal-CRM/relationship app specifically, but multiple live identical marks exist in Class 9 broadly. Many unrelated EMBERs already coexist across software niches, which cuts both ways. The suffixed listing name ("Ember — thoughtful check-ins") helps discoverability but is not legal clearance. For a free indie app the practical risk is low; before any paid/commercial push, have a trademark attorney run a real clearance.
