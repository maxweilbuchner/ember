# App Store listing copy

Draft copy for the App Store Connect version page and TestFlight. Character limits noted per field.

## Name (30 chars max)

> Ember — thoughtful check-ins

28 chars. Per spec §5.4 — bare "Ember" is a crowded namespace.

## Subtitle (30 chars max)

> Keep the people you love warm

29 chars. The spec's working tagline.

## Promotional text (170 chars max, editable without review)

> Ember lives entirely on your device: no accounts, no cloud, no streaks. Gentle nudges to reach out to the people who matter — when it's been a while, never as a debt.

## Description (4000 chars max)

> Some friendships don't need daily contact. They just need to not go cold.
>
> Ember is a small, private place to tend the relationships you care about. Add the people who matter, jot down moments — a call, a coffee, something they told you — and Ember quietly suggests when it might be time to reach out again. Never as a streak, a score, or a guilt trip. Just a warm nudge.
>
> WHAT IT DOES
> • Today: a short, calm list of people it might be time to check in on — with a reason, not a deadline
> • Moments: capture what happened — Ember notices who you mentioned and files it with the right person
> • Drafted openers: a suggested first line when reaching out feels hard, written from your own notes
> • Birthdays: remembered from your contacts, surfaced in time
> • Capture from anywhere: a lock-screen widget for jotting a moment the second it happens
>
> WHAT IT NEVER DOES
> • No accounts, no cloud, no sync servers — everything stays on your device
> • No analytics, no ads, no third-party code
> • No guilt mechanics: Ember never counts the days since you talked, never shames you, never turns friendship into a to-do list
>
> PRIVATE BY DESIGN
> Your notes are yours. Ember stores everything locally, protected by iOS encryption, with an optional Face ID lock. Contacts access is read-only and on-device — used only to show names, photos, and birthdays. The writing help runs on Apple's on-device intelligence; nothing is sent to any server. Export everything as a zip, or erase it all, any time.
>
> Ember is for the relationships that matter over years, not weeks. Keep them warm.

## Keywords (100 chars max, comma-separated — don't repeat words from name/subtitle)

> personal crm,keep in touch,relationships,friends,family,journal,birthday,reminder,mindful,contact

97 chars.

## URLs

- Support URL: `https://<pages-domain>/#support`
- Privacy Policy URL: `https://<pages-domain>/#privacy`
- Marketing URL: optional, same page.

(Page lives at `docs/index.html`, ready for GitHub Pages → main branch, `/docs` folder.)

## TestFlight — Test Information

**Beta App Description:**

> Ember is a privacy-first personal CRM: gentle reminders to check in on people you care about, with all data on-device. No account needed — grant Contacts and Notifications when asked, add a few people, and capture a moment or two.

**What to test (per-build notes, first build):**

> - Link a few people to real contacts; check name/photo/birthday appear
> - Capture a moment mentioning someone by name — do the right people get detected?
> - Try a drafted opener from a nudge (needs Apple Intelligence enabled)
> - Turn on the app lock in Settings; background and reopen the app
> - Add the lock-screen capture widget and jot a moment from there
> - Export everything from Settings and open the zip in Files

**Feedback email:** maxweilbuchner@gmail.com

## Screenshots — done, in `Screenshots/`

Run `Scripts/screenshots.sh` to regenerate: it builds Debug, seeds fictional data
(`DemoSeed`, `--demo-seed`, compiled out of Release), navigates via DEBUG deep links,
and captures 6.9-inch PNGs (1320 × 2868, the only required size) on the
iPhone 17 Pro Max simulator.

1. `01-today` — nudge cards + upcoming birthday
2. `02-capture-chips` — capture with AI extraction chips
3. `03-person` — Anna's detail page (timeline, ideas)
4. `04-compose` — drafted opener for Priya
5. `05-journal` — journal timeline
6. `06-people` — tiered people list
7. `07-settings` — privacy settings (app lock, export & delete)

Upload order suggestion: 01, 04, 02, 03, 07 (privacy is the differentiator — keep it in the first five that show on the product page); 05/06 optional.
