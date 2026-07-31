// TestDoubles.swift

import Foundation
@testable import Ember

/// Records every scheduling call, so tests assert exactly what would have
/// reached UNUserNotificationCenter. Pending identifiers behave like the real
/// center: adds append, removes filter.
actor SchedulerSpy: NotificationScheduling {
    private(set) var added: [NotificationSpec] = []
    private(set) var removedPending: [String] = []
    private(set) var removedDelivered: [String] = []
    private(set) var pending: [String] = []
    private(set) var delivered: [String] = []

    func pendingIdentifiers() -> [String] { pending }

    func deliveredIdentifiers() -> [String] { delivered }

    func add(_ spec: NotificationSpec) {
        added.append(spec)
        pending.append(spec.identifier)
    }

    func removePending(identifiers: [String]) {
        removedPending.append(contentsOf: identifiers)
        pending.removeAll { identifiers.contains($0) }
    }

    func removeDelivered(identifiers: [String]) {
        removedDelivered.append(contentsOf: identifiers)
        delivered.removeAll { identifiers.contains($0) }
    }

    func seedPending(_ identifiers: [String]) {
        pending = identifiers
    }

    func seedDelivered(_ identifiers: [String]) {
        delivered = identifiers
    }
}

/// In-memory contact resolution — tests never touch the live CNContactStore.
nonisolated struct StubContacts: ContactResolving {
    var contactsByID: [String: ResolvedContact] = [:]

    func resolve(_ contactID: String) async -> ResolvedContact? {
        contactsByID[contactID]
    }
}

extension ResolvedContact {
    static func fixture(
        id: String,
        name: String = "Contact",
        birthday: DateComponents? = nil
    ) -> ResolvedContact {
        ResolvedContact(
            id: id,
            givenName: name,
            familyName: "",
            nickname: "",
            displayName: name,
            thumbnailData: nil,
            birthday: birthday,
            phoneNumbers: []
        )
    }
}

/// Records birthday write-backs instead of touching the real address book, and
/// can refuse them the way a deleted contact or read-only account would.
actor StubContactWriter: ContactWriting {
    private(set) var writes: [(contactID: String, birthday: DateComponents?)] = []
    private var shouldFail = false

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func setBirthday(_ birthday: DateComponents?, forContactID contactID: String) throws {
        if shouldFail { throw ContactWriteError.unresolvable }
        writes.append((contactID, birthday))
    }
}

/// A gregorian calendar pinned to an explicit time zone, so date math in tests
/// is deterministic regardless of the machine running them.
nonisolated func fixedCalendar(_ timeZoneIdentifier: String = "Europe/Berlin") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timeZoneIdentifier)!
    return calendar
}
