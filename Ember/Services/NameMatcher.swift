// NameMatcher.swift

import Foundation

nonisolated struct NameCandidate: Sendable, Hashable {
    var id: String
    var givenName: String
    var familyName: String
    var nickname: String
    var displayName: String
}

/// Pure, case- and diacritic-insensitive name matching over given/family/nickname.
/// Supports "Julia", "Dani", "Max W" style queries. Used by contact search and
/// (in M4) by extraction name resolution.
nonisolated enum NameMatcher {
    static func fold(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
    }

    static func matches(_ candidate: NameCandidate, query: String) -> Bool {
        let foldedQuery = fold(query)
        let tokens = foldedQuery.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return false }

        let given = fold(candidate.givenName)
        let family = fold(candidate.familyName)
        let nick = fold(candidate.nickname)
        let display = fold(candidate.displayName)

        if display.hasPrefix(foldedQuery) { return true }

        if tokens.count == 1 {
            let token = tokens[0]
            return given.hasPrefix(token) || nick.hasPrefix(token) || family.hasPrefix(token)
        }

        // Multi-token, e.g. "Max W": first token against given/nickname,
        // remaining tokens must prefix-match the family name.
        let first = tokens[0]
        let firstMatches = given.hasPrefix(first) || nick.hasPrefix(first)
        let restMatches = tokens.dropFirst().allSatisfy { family.hasPrefix($0) }
        return firstMatches && restMatches
    }

    static func candidates(matching query: String, in candidates: [NameCandidate]) -> [NameCandidate] {
        candidates.filter { matches($0, query: query) }
    }

    /// Resolution for an extracted name: exact full-name matches win, then exact
    /// given/nickname matches, then prefix matches. More than one result = ambiguous;
    /// zero = unknown name (offer "create unlinked Person").
    static func resolve(name: String, in candidates: [NameCandidate]) -> [NameCandidate] {
        let folded = fold(name)
        guard !folded.isEmpty else { return [] }

        let exactFull = candidates.filter {
            fold($0.displayName) == folded || fold($0.givenName + " " + $0.familyName) == folded
        }
        if !exactFull.isEmpty { return exactFull }

        let exactGiven = candidates.filter {
            fold($0.givenName) == folded || fold($0.nickname) == folded
        }
        if !exactGiven.isEmpty { return exactGiven }

        return candidates.filter { matches($0, query: name) }
    }
}
