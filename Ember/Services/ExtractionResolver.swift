// ExtractionResolver.swift

import Foundation

/// Pure post-processing: extracted names → existing Persons, known contacts, or
/// unknowns. Priority: an Ember Person always beats a raw contact; one match is
/// certain, several are ambiguous (→ ask), none is unknown (→ offer to create).

nonisolated struct PersonRef: Sendable, Hashable {
    var id: UUID
    var displayName: String
}

nonisolated enum NameResolutionOutcome: Sendable, Hashable {
    case person(UUID)
    case ambiguousPersons([UUID])
    case contact(NameCandidate)
    case ambiguousContacts([NameCandidate])
    case unknown
}

nonisolated struct MentionSuggestion: Sendable, Hashable, Identifiable {
    var name: String
    var outcome: NameResolutionOutcome
    var interacted: Bool
    var channelGuess: Channel
    var lifeEvent: String?

    var id: String { name }
}

nonisolated struct CommitmentSuggestion: Sendable, Hashable, Identifiable {
    var text: String
    var personName: String?
    var personOutcome: NameResolutionOutcome?

    var id: String { text }
}

nonisolated struct EntrySuggestions: Sendable, Hashable {
    var entryID: UUID
    var mentions: [MentionSuggestion] = []
    var commitments: [CommitmentSuggestion] = []

    var isEmpty: Bool { mentions.isEmpty && commitments.isEmpty }
}

nonisolated enum ExtractionResolver {
    static func resolve(
        _ result: ExtractionResult,
        entryID: UUID,
        persons: [PersonRef],
        contacts: [NameCandidate]
    ) -> EntrySuggestions {
        var seenNames = Set<String>()
        var mentions: [MentionSuggestion] = []
        for extracted in result.people {
            let name = extracted.name.trimmingCharacters(in: .whitespaces)
            let key = NameMatcher.fold(name)
            guard !key.isEmpty, seenNames.insert(key).inserted else { continue }
            mentions.append(MentionSuggestion(
                name: name,
                outcome: resolveName(name, persons: persons, contacts: contacts),
                interacted: extracted.interacted,
                channelGuess: extracted.channelGuess,
                lifeEvent: extracted.lifeEvent
            ))
        }

        var seenCommitments = Set<String>()
        var commitments: [CommitmentSuggestion] = []
        for extracted in result.commitments {
            let text = extracted.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, seenCommitments.insert(NameMatcher.fold(text)).inserted else { continue }
            commitments.append(CommitmentSuggestion(
                text: text,
                personName: extracted.personName,
                personOutcome: extracted.personName.map { resolveName($0, persons: persons, contacts: contacts) }
            ))
        }

        return EntrySuggestions(entryID: entryID, mentions: mentions, commitments: commitments)
    }

    static func resolveName(
        _ name: String,
        persons: [PersonRef],
        contacts: [NameCandidate]
    ) -> NameResolutionOutcome {
        let personMatches = NameMatcher.resolve(name: name, in: persons.map(\.nameCandidate))
        if personMatches.count == 1, let id = UUID(uuidString: personMatches[0].id) {
            return .person(id)
        }
        if personMatches.count > 1 {
            return .ambiguousPersons(personMatches.compactMap { UUID(uuidString: $0.id) })
        }

        let contactMatches = NameMatcher.resolve(name: name, in: contacts)
        if contactMatches.count == 1 {
            return .contact(contactMatches[0])
        }
        if contactMatches.count > 1 {
            return .ambiguousContacts(contactMatches)
        }

        return .unknown
    }
}

nonisolated extension PersonRef {
    /// Person display names split into given/family so NameMatcher's rules
    /// ("Julia", "Max W") apply to Ember Persons exactly as they do to contacts.
    var nameCandidate: NameCandidate {
        let parts = displayName.split(separator: " ", maxSplits: 1).map(String.init)
        return NameCandidate(
            id: id.uuidString,
            givenName: parts.first ?? displayName,
            familyName: parts.count > 1 ? parts[1] : "",
            nickname: "",
            displayName: displayName
        )
    }
}
