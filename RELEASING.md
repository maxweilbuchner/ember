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
- [ ] Trademark check
- [ ] Screenshots + listing copy
