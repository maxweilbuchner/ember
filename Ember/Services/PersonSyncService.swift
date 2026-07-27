// PersonSyncService.swift

import Foundation
import SwiftData

/// Keeps `Person.displayNameCache` fresh and degrades Persons to "unlinked" when
/// their contact was deleted or merged. Unresolvable contactIDs are a NORMAL state,
/// not an error (spec §8) — with limited Contacts access a missing contact may just
/// be outside the selected set, so unlinking only happens under full access.
actor PersonSyncService {
    private let container: ModelContainer
    private let contacts: ContactService

    init(container: ModelContainer, contacts: ContactService) {
        self.container = container
        self.contacts = contacts
    }

    func refreshAll() async {
        let context = ModelContext(container)
        let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        let contactIDs = people.compactMap(\.contactID)
        guard !contactIDs.isEmpty else { return }
        let resolutions = await contacts.resolutions(for: contactIDs)
        let hasFullAccess = ContactService.authorizationStatus == .authorized
        apply(resolutions: resolutions, hasFullAccess: hasFullAccess, in: context)
    }

    /// Test seam: apply pre-computed resolutions without touching CNContactStore.
    func apply(resolutions: [ContactResolution], hasFullAccess: Bool) {
        let context = ModelContext(container)
        apply(resolutions: resolutions, hasFullAccess: hasFullAccess, in: context)
    }

    private func apply(resolutions: [ContactResolution], hasFullAccess: Bool, in context: ModelContext) {
        let resolutionsByID = Dictionary(resolutions.map { ($0.contactID, $0) }, uniquingKeysWith: { first, _ in first })
        let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        for person in people {
            guard let contactID = person.contactID, let resolution = resolutionsByID[contactID] else { continue }
            if let name = resolution.displayName {
                if !name.isEmpty {
                    person.displayNameCache = name
                }
            } else if hasFullAccess {
                // Contact is gone: unlink, keep name cache and full history intact.
                person.contactID = nil
            }
        }
        try? context.save()
    }
}
