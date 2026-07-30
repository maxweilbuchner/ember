// AppServices.swift

import Foundation
import SwiftData
import SwiftUI

/// Dependency container injected via the SwiftUI environment. Services are actors
/// receiving the shared ModelContainer — no singletons, and no SwiftUI property
/// wrappers outside views (spec §4/§8).
@Observable
@MainActor
final class AppServices {
    let container: ModelContainer
    let contacts: ContactService
    let personSync: PersonSyncService
    let nudgeEngine: NudgeEngine
    let dateEngine: DateEngine
    let extraction: any ExtractionProviding
    let drafts: any DraftProviding
    let export: ExportService
    let security = SecurityService()
    let images = ImageStore()
    let router = AppRouter()

    /// In-memory AI suggestions per entry — never persisted: suggestions become
    /// data only when the user confirms a chip.
    var entrySuggestions: [UUID: EntrySuggestions] = [:]
    /// Entries whose extraction is in flight — drives the "Looking for people…"
    /// row so "thinking" is distinguishable from "found nobody".
    var extractingEntryIDs: Set<UUID> = []
    var modelAvailability: ModelAvailability = .current

    init(container: ModelContainer) {
        self.container = container
        let contacts = ContactService()
        self.contacts = contacts
        self.personSync = PersonSyncService(container: container, contacts: contacts)
        self.nudgeEngine = NudgeEngine(container: container, contacts: contacts)
        self.dateEngine = DateEngine(container: container, contacts: contacts)
        #if DEBUG
        if DemoSeed.isActive {
            self.extraction = DemoExtractionProvider()
            self.drafts = DemoDraftProvider()
        } else {
            self.extraction = ExtractionService()
            self.drafts = DraftService()
        }
        #else
        self.extraction = ExtractionService()
        self.drafts = DraftService()
        #endif
        self.export = ExportService(container: container)
    }

    /// One-time startup work, run from the root view's task.
    func startUp() async {
        await nudgeEngine.setDraftProvider(drafts)
        await contacts.startObserving()
        let personSync = personSync
        await contacts.onStoreChange { [weak personSync] in
            await personSync?.refreshAll()
        }
        await personSync.refreshAll()
    }

    /// Fire-and-forget after an entry saves: extract → resolve → auto-tag the
    /// confident matches → publish whatever still needs a tap. The entry stays
    /// `.pending` only while extraction hasn't successfully completed, so a
    /// failed or unavailable run is retried on the next foreground.
    func extractEntry(id: UUID, text: String) async {
        modelAvailability = .current
        guard modelAvailability == .available else { return }

        extractingEntryIDs.insert(id)
        defer { extractingEntryIDs.remove(id) }

        let people = ((try? container.mainContext.fetch(FetchDescriptor<Person>())) ?? [])
            .filter { !$0.isPlaceholder }
        let personRefs: [PersonRef] = people.map { PersonRef(id: $0.id, displayName: $0.displayNameCache) }
        let contactCandidates = await contacts.nameCandidates()

        var candidateNames = personRefs.map(\.displayName)
        candidateNames.append(contentsOf: contactCandidates.map(\.displayName))
        var seen = Set<String>()
        candidateNames = candidateNames.filter { seen.insert(NameMatcher.fold($0)).inserted }

        guard let result = await extraction.extract(entryText: text, candidateNames: candidateNames) else { return }
        // Ground every suggestion in the entry text — small models sometimes
        // echo the candidate list back as "mentioned people".
        let grounded = ExtractionResolver.grounded(result, in: text)
        let suggestions = ExtractionResolver.resolve(grounded, entryID: id, persons: personRefs, contacts: contactCandidates)

        let context = container.mainContext
        guard let entry = (try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })))?.first else {
            return
        }
        let remaining = MentionApplier.autoApply(suggestions, to: entry, people: people, context: context)
        entrySuggestions[id] = remaining.isEmpty ? nil : remaining
        // Extraction ran: the entry is done, whether or not it named anybody.
        entry.extractionState = .reviewed
        try? context.save()
    }

    /// Suggestions live in memory only, so an app relaunch mid-extraction would
    /// otherwise strand an entry forever. Re-runs recent entries that never
    /// completed extraction.
    func retryPendingExtractions(now: Date = .now) async {
        #if DEBUG
        // The demo seed hand-curates its suggestions; a real extraction pass
        // would overwrite them and make screenshots non-deterministic.
        if DemoSeed.isActive { return }
        #endif
        guard ModelAvailability.current == .available else { return }
        let cutoff = now.addingTimeInterval(-24 * 3600)
        let stale = ((try? container.mainContext.fetch(FetchDescriptor<Entry>())) ?? [])
            .filter { $0.extractionState == .pending && $0.date > cutoff && !extractingEntryIDs.contains($0.id) }
            .sorted { $0.date > $1.date }
        for entry in stale {
            await extractEntry(id: entry.id, text: entry.text)
        }
    }

    /// Clean-up after a person is deleted, anonymized, or merged away: remap or
    /// drop in-memory suggestions, close their pending nudges (and pull the
    /// notifications), and resweep occasion notifications.
    func personRemoved(_ personID: UUID, mergedInto targetID: UUID? = nil) async {
        remapSuggestions(from: personID, to: targetID)
        await nudgeEngine.personRemoved(personID)
        await dateEngine.refresh()
    }

    /// Merge: `.person(source)` → `.person(target)` (collapsing ambiguity when
    /// one candidate remains). Removal without a target: drop that entry's
    /// suggestions — it stays pending, and manual review is the fallback.
    private func remapSuggestions(from source: UUID, to target: UUID?) {
        for (entryID, suggestions) in entrySuggestions {
            var suggestions = suggestions
            var touched = false
            var dropped = false

            func remap(_ outcome: NameResolutionOutcome) -> NameResolutionOutcome {
                switch outcome {
                case .person(let id) where id == source:
                    touched = true
                    guard let target else { dropped = true; return outcome }
                    return .person(target)
                case .ambiguousPersons(let ids) where ids.contains(source):
                    touched = true
                    guard let target else { dropped = true; return outcome }
                    var seen = Set<UUID>()
                    let remapped = ids.map { $0 == source ? target : $0 }
                        .filter { seen.insert($0).inserted }
                    return remapped.count == 1 ? .person(remapped[0]) : .ambiguousPersons(remapped)
                default:
                    return outcome
                }
            }

            suggestions.mentions = suggestions.mentions.map {
                var mention = $0
                mention.outcome = remap(mention.outcome)
                return mention
            }
            suggestions.commitments = suggestions.commitments.map {
                var commitment = $0
                commitment.personOutcome = commitment.personOutcome.map(remap)
                return commitment
            }

            if dropped {
                entrySuggestions[entryID] = nil
            } else if touched {
                entrySuggestions[entryID] = suggestions
            }
        }
    }

    /// Called whenever the app becomes active: BGTask is best-effort,
    /// so staleness is re-checked in the foreground.
    func becameActive() async {
        await nudgeEngine.evaluateIfStale()
        await dateEngine.refresh()
        await retryPendingExtractions()
    }
}

@Observable
@MainActor
final class AppRouter {
    var selectedTab: AppTab = .today
    /// Set when a deep link asks for the capture field (e.g. lock-screen widget).
    var captureRequested = false
    /// Person to open from a nudge notification tap; Compose proper arrives in M4.
    var composePersonID: UUID?
    #if DEBUG
    // Driven by the DEBUG deep links (screenshot script) only.
    var detailPersonID: UUID?
    var settingsRequested = false
    #endif

    func handle(_ link: DeepLink) {
        switch link {
        case .capture:
            selectedTab = .today
            captureRequested = true
        case .compose(let personID):
            composePersonID = personID
        #if DEBUG
        case .tab(let tab):
            composePersonID = nil
            selectedTab = tab
        case .person(let personID):
            composePersonID = nil
            selectedTab = .people
            detailPersonID = personID
        case .settings:
            composePersonID = nil
            selectedTab = .people
            settingsRequested = true
        #endif
        }
    }
}

nonisolated enum AppTab: Hashable, Sendable {
    case today
    case people
    case journal
}
