// NameMatcherTests.swift

import Foundation
import Testing
@testable import Ember

@Suite("NameMatcher")
struct NameMatcherTests {
    private func candidate(
        id: String = "c1",
        given: String,
        family: String = "",
        nickname: String = ""
    ) -> NameCandidate {
        NameCandidate(
            id: id,
            givenName: given,
            familyName: family,
            nickname: nickname,
            displayName: [given, family].filter { !$0.isEmpty }.joined(separator: " ")
        )
    }

    // MARK: compactName

    @Test func compactNameUsesFirstNameAndLastInitial() {
        #expect(NameMatcher.compactName("Julia Katharina Schwarenthorer") == "Julia S")
        #expect(NameMatcher.compactName("Anna Schmid") == "Anna S")
    }

    @Test func compactNameLeavesSingleWordsAlone() {
        #expect(NameMatcher.compactName("Someone") == "Someone")
        #expect(NameMatcher.compactName("Anna") == "Anna")
        #expect(NameMatcher.compactName("") == "")
    }

    @Test func compactNameKeepsDiacritics() {
        #expect(NameMatcher.compactName("Tomáš Novák") == "Tomáš N")
    }

    // MARK: matches

    @Test func matchesGivenNamePrefix() {
        let julia = candidate(given: "Julia", family: "Schmidt")
        #expect(NameMatcher.matches(julia, query: "Julia"))
        #expect(NameMatcher.matches(julia, query: "jul"))
        #expect(!NameMatcher.matches(julia, query: "Anna"))
    }

    @Test func matchesNickname() {
        let daniela = candidate(given: "Daniela", family: "Huber", nickname: "Dani")
        #expect(NameMatcher.matches(daniela, query: "Dani"))
        #expect(NameMatcher.matches(daniela, query: "dani"))
    }

    @Test func matchesFamilyName() {
        let anna = candidate(given: "Anna", family: "Lopez")
        #expect(NameMatcher.matches(anna, query: "Lopez"))
    }

    @Test func matchesGivenPlusFamilyInitial() {
        let max = candidate(given: "Max", family: "Weilbuchner")
        #expect(NameMatcher.matches(max, query: "Max W"))
        #expect(NameMatcher.matches(max, query: "max weil"))
        #expect(!NameMatcher.matches(max, query: "Max B"))
    }

    @Test func caseAndDiacriticInsensitive() {
        let mueller = candidate(given: "Jörg", family: "Müller")
        #expect(NameMatcher.matches(mueller, query: "jorg"))
        #expect(NameMatcher.matches(mueller, query: "muller"))
        #expect(NameMatcher.matches(mueller, query: "MÜLLER"))
        let jose = candidate(given: "José", family: "García")
        #expect(NameMatcher.matches(jose, query: "jose garcia"))
    }

    @Test func emptyQueryNeverMatches() {
        let julia = candidate(given: "Julia")
        #expect(!NameMatcher.matches(julia, query: ""))
        #expect(!NameMatcher.matches(julia, query: "   "))
    }

    // MARK: resolve (extraction post-processing)

    @Test func resolveExactGivenNameBeatsPrefix() {
        let julia = candidate(id: "julia", given: "Julia", family: "Schmidt")
        let julian = candidate(id: "julian", given: "Julian", family: "Berg")
        let resolved = NameMatcher.resolve(name: "Julia", in: [julia, julian])
        #expect(resolved.map(\.id) == ["julia"])
    }

    @Test func resolveFullNameIsUnambiguous() {
        let a = candidate(id: "a", given: "Max", family: "Weilbuchner")
        let b = candidate(id: "b", given: "Max", family: "Berger")
        let resolved = NameMatcher.resolve(name: "Max Weilbuchner", in: [a, b])
        #expect(resolved.map(\.id) == ["a"])
    }

    @Test func resolveAmbiguousReturnsAllMatches() {
        let a = candidate(id: "a", given: "Max", family: "Weilbuchner")
        let b = candidate(id: "b", given: "Max", family: "Berger")
        let resolved = NameMatcher.resolve(name: "Max", in: [a, b])
        #expect(Set(resolved.map(\.id)) == ["a", "b"])
    }

    @Test func resolveNicknameExactly() {
        let daniela = candidate(id: "d", given: "Daniela", family: "Huber", nickname: "Dani")
        let daniel = candidate(id: "dl", given: "Daniel", family: "Kraus")
        let resolved = NameMatcher.resolve(name: "Dani", in: [daniela, daniel])
        #expect(resolved.map(\.id) == ["d"])
    }

    @Test func resolveUnknownNameReturnsEmpty() {
        let julia = candidate(given: "Julia")
        #expect(NameMatcher.resolve(name: "Zebediah", in: [julia]).isEmpty)
        #expect(NameMatcher.resolve(name: "", in: [julia]).isEmpty)
    }
}
