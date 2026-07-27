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
    let birthdayEngine: BirthdayEngine
    let extraction: any ExtractionProviding
    let drafts: any DraftProviding
    let export: ExportService
    let security = SecurityService()
    let images = ImageStore()
    let router = AppRouter()

    /// In-memory AI suggestions per entry — never persisted: suggestions become
    /// data only when the user confirms a chip.
    var entrySuggestions: [UUID: EntrySuggestions] = [:]
    var modelAvailability: ModelAvailability = .current

    init(container: ModelContainer) {
        self.container = container
        let contacts = ContactService()
        self.contacts = contacts
        self.personSync = PersonSyncService(container: container, contacts: contacts)
        self.nudgeEngine = NudgeEngine(container: container, contacts: contacts)
        self.birthdayEngine = BirthdayEngine(container: container, contacts: contacts)
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

    /// Fire-and-forget after an entry saves: extract → resolve → publish chips.
    /// Any failure leaves the entry pending for the manual review sheet.
    func extractEntry(id: UUID, text: String) async {
        modelAvailability = .current
        guard modelAvailability == .available else { return }

        let personRefs: [PersonRef] = ((try? container.mainContext.fetch(FetchDescriptor<Person>())) ?? [])
            .map { PersonRef(id: $0.id, displayName: $0.displayNameCache) }
        let contactCandidates = await contacts.nameCandidates()

        var candidateNames = personRefs.map(\.displayName)
        candidateNames.append(contentsOf: contactCandidates.map(\.displayName))
        var seen = Set<String>()
        candidateNames = candidateNames.filter { seen.insert(NameMatcher.fold($0)).inserted }

        guard let result = await extraction.extract(entryText: text, candidateNames: candidateNames) else { return }
        let suggestions = ExtractionResolver.resolve(result, entryID: id, persons: personRefs, contacts: contactCandidates)
        if !suggestions.isEmpty {
            entrySuggestions[id] = suggestions
        }
    }

    /// Called whenever the app becomes active: BGTask is best-effort,
    /// so staleness is re-checked in the foreground.
    func becameActive() async {
        await nudgeEngine.evaluateIfStale()
        await birthdayEngine.refresh()
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
