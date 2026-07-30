// BirthdayWriteBack.swift

import Foundation
import SwiftData

/// Saving a birthday, and optionally mirroring it onto the linked contact card.
///
/// On a successful write the manual copy is cleared: the card now owns the
/// birthday, `BirthdayResolution` reads it from there, and there is no second
/// copy left to drift. A failed write is a normal state (contact deleted,
/// limited-access selection, read-only account) — the birthday simply stays in
/// Ember, exactly as it did before this feature existed.
@MainActor
enum BirthdayWriteBack {
    /// Returns true when the birthday reached the contact card.
    @discardableResult
    static func save(
        _ birthday: DateComponents?,
        for person: Person,
        alsoToContacts: Bool,
        writer: any ContactWriting,
        context: ModelContext
    ) async -> Bool {
        // Ember's own copy is written first and unconditionally, so nothing is
        // lost if the card write fails.
        person.manualBirthday = birthday
        try? context.save()

        guard alsoToContacts, let contactID = person.contactID else { return false }

        do {
            try await writer.setBirthday(birthday, forContactID: contactID)
            person.manualBirthday = nil
            try? context.save()
            return true
        } catch {
            return false
        }
    }
}
