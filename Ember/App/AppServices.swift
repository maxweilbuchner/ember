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
    let images = ImageStore()
    let router = AppRouter()

    init(container: ModelContainer) {
        self.container = container
        let contacts = ContactService()
        self.contacts = contacts
        self.personSync = PersonSyncService(container: container, contacts: contacts)
        self.nudgeEngine = NudgeEngine(container: container, contacts: contacts)
        self.birthdayEngine = BirthdayEngine(container: container, contacts: contacts)
    }

    /// One-time startup work, run from the root view's task.
    func startUp() async {
        await contacts.startObserving()
        let personSync = personSync
        await contacts.onStoreChange { [weak personSync] in
            await personSync?.refreshAll()
        }
        await personSync.refreshAll()
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

    func handle(_ link: DeepLink) {
        switch link {
        case .capture:
            selectedTab = .today
            captureRequested = true
        case .compose(let personID):
            composePersonID = personID
        }
    }
}

nonisolated enum AppTab: Hashable, Sendable {
    case today
    case people
    case journal
}
