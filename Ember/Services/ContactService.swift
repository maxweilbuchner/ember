// ContactService.swift

import Contacts
import Foundation

nonisolated struct ResolvedContact: Sendable, Hashable {
    var id: String
    var givenName: String
    var familyName: String
    var nickname: String
    var displayName: String
    var thumbnailData: Data?
    var birthday: DateComponents?
    var phoneNumbers: [LabeledNumber]
    var relations: [ContactRelationItem] = []

    var nameCandidate: NameCandidate {
        NameCandidate(id: id, givenName: givenName, familyName: familyName, nickname: nickname, displayName: displayName)
    }
}

nonisolated struct LabeledNumber: Sendable, Hashable {
    var label: String
    var number: String
}

/// The one contact capability the engines need — a seam so tests never touch
/// the live CNContactStore.
protocol ContactResolving: Sendable {
    func resolve(_ contactID: String) async -> ResolvedContact?
}

extension ContactService: ContactResolving {}

/// Live resolution of `contactID → (name, photo, birthday, phone numbers)` with an
/// in-memory cache, invalidated on CNContactStoreDidChange. Ember never duplicates
/// Contacts data into its store — and never requests CNContactNoteKey.
actor ContactService {
    private let store = CNContactStore()
    private var cache: [String: ResolvedContact] = [:]
    private var allContactsCache: [ResolvedContact]?
    private var observationTask: Task<Void, Never>?
    private var changeHandlers: [@Sendable () async -> Void] = []

    private var keysToFetch: [CNKeyDescriptor] {
        [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactRelationsKey as CNKeyDescriptor,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        ]
    }

    // MARK: Permission

    nonisolated static var authorizationStatus: CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    @discardableResult
    func requestAccess() async -> CNAuthorizationStatus {
        _ = try? await store.requestAccess(for: .contacts)
        return Self.authorizationStatus
    }

    // MARK: Resolution

    func resolve(_ contactID: String) -> ResolvedContact? {
        if let cached = cache[contactID] { return cached }
        guard let contact = try? store.unifiedContact(withIdentifier: contactID, keysToFetch: keysToFetch) else {
            return nil
        }
        let resolved = Self.map(contact)
        cache[contactID] = resolved
        return resolved
    }

    /// Batch resolution for PersonSyncService. `displayName == nil` means the store
    /// definitively has no contact with that identifier (deleted or merged away).
    func resolutions(for contactIDs: [String]) -> [ContactResolution] {
        contactIDs.map { ContactResolution(contactID: $0, displayName: resolve($0)?.displayName) }
    }

    func allContacts() -> [ResolvedContact] {
        if let cached = allContactsCache { return cached }
        var results: [ResolvedContact] = []
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        request.sortOrder = .givenName
        try? store.enumerateContacts(with: request) { contact, _ in
            results.append(Self.map(contact))
        }
        allContactsCache = results
        for resolved in results {
            cache[resolved.id] = resolved
        }
        return results
    }

    func search(_ query: String) -> [ResolvedContact] {
        let all = allContacts()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return all }
        return all.filter { NameMatcher.matches($0.nameCandidate, query: trimmed) }
    }

    func nameCandidates() -> [NameCandidate] {
        allContacts().map(\.nameCandidate)
    }

    /// The user's own card, chosen manually in Settings (iOS exposes no me-card
    /// API). nil = not set, or the chosen contact is gone — both normal states.
    func meContact() -> ResolvedContact? {
        MeCard.contactID.flatMap { resolve($0) }
    }

    // MARK: Change observation

    func startObserving() {
        guard observationTask == nil else { return }
        observationTask = Task { [weak self] in
            let stream = AsyncStream<Void> { continuation in
                nonisolated(unsafe) let token = NotificationCenter.default.addObserver(
                    forName: .CNContactStoreDidChange, object: nil, queue: nil
                ) { _ in
                    continuation.yield()
                }
                continuation.onTermination = { _ in
                    NotificationCenter.default.removeObserver(token)
                }
            }
            for await _ in stream {
                await self?.storeDidChange()
            }
        }
    }

    func onStoreChange(_ handler: @escaping @Sendable () async -> Void) {
        changeHandlers.append(handler)
    }

    private func storeDidChange() async {
        cache.removeAll()
        allContactsCache = nil
        for handler in changeHandlers {
            await handler()
        }
    }

    // MARK: Mapping

    private nonisolated static func map(_ contact: CNContact) -> ResolvedContact {
        let formatted = CNContactFormatter.string(from: contact, style: .fullName)
        let fallback = [contact.givenName, contact.familyName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let displayName = formatted ?? (fallback.isEmpty ? contact.nickname : fallback)
        return ResolvedContact(
            id: contact.identifier,
            givenName: contact.givenName,
            familyName: contact.familyName,
            nickname: contact.nickname,
            displayName: displayName,
            thumbnailData: contact.thumbnailImageData,
            birthday: contact.birthday,
            phoneNumbers: contact.phoneNumbers.map {
                LabeledNumber(
                    label: $0.label.map { CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: $0) } ?? "",
                    number: $0.value.stringValue
                )
            },
            relations: contact.contactRelations.map {
                ContactRelationItem(
                    rawLabel: $0.label ?? "",
                    localizedLabel: $0.label.map { CNLabeledValue<CNContactRelation>.localizedString(forLabel: $0) } ?? "",
                    name: $0.value.name
                )
            }
        )
    }
}

/// Which contact card is *you* — a UI preference (like the lock toggle), read
/// only by views to derive relation labels; engines never touch it.
nonisolated enum MeCard {
    private static let key = "meContactID"

    static var contactID: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
