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
    /// Deterministic backstop against candidate-list regurgitation: an extracted
    /// person survives only when their name is grounded in the entry text — the
    /// full folded name on word boundaries, or the first name token (the model
    /// sometimes normalises "Julia" as written to a candidate's full name).
    /// Commitments keep their text (paraphrase can't be string-matched) but an
    /// ungrounded personName is dropped.
    static func grounded(_ result: ExtractionResult, in entryText: String) -> ExtractionResult {
        let words = wordSet(of: entryText)
        let paddedText = " " + words.joined(separator: " ") + " "

        /// nil = ungrounded. Otherwise the name as the entry actually writes it:
        /// a model that expanded "Anna" to a candidate's full name ("Anna Haro")
        /// is trimmed back, so resolution matches on what the user wrote rather
        /// than on the reference spelling the model reached for.
        func groundedName(_ name: String) -> String? {
            let nameWords = wordSet(of: name)
            guard let firstToken = nameWords.first else { return nil }
            if paddedText.contains(" " + nameWords.joined(separator: " ") + " ") { return name }
            guard firstToken.count >= 2, words.contains(firstToken) else { return nil }
            return name.split(separator: " ").first.map(String.init) ?? name
        }

        func appears(_ name: String) -> Bool {
            groundedName(name) != nil
        }

        return ExtractionResult(
            people: result.people.compactMap { person in
                guard let name = groundedName(person.name) else { return nil }
                var person = person
                person.name = name
                return person
            },
            commitments: result.commitments.map { commitment in
                var commitment = commitment
                if let name = commitment.personName, !appears(name) {
                    commitment.personName = nil
                }
                return commitment
            }
        )
    }

    private static func wordSet(of text: String) -> [String] {
        let cleaned = String(NameMatcher.fold(text).map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        })
        return cleaned.split(separator: " ").map(String.init)
    }

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
