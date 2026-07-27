// ExtractionResolverTests.swift

import Foundation
import Testing
@testable import Ember

@Suite("Extraction resolver")
struct ExtractionResolverTests {
    private let juliaID = UUID()
    private let maxAID = UUID()
    private let maxBID = UUID()

    private var persons: [PersonRef] {
        [
            PersonRef(id: juliaID, displayName: "Julia Schmidt"),
            PersonRef(id: maxAID, displayName: "Max Weilbuchner"),
            PersonRef(id: maxBID, displayName: "Max Berger"),
        ]
    }

    private var contacts: [NameCandidate] {
        [
            NameCandidate(id: "c-julia", givenName: "Julia", familyName: "Schmidt", nickname: "", displayName: "Julia Schmidt"),
            NameCandidate(id: "c-anna", givenName: "Anna", familyName: "Lopez", nickname: "", displayName: "Anna Lopez"),
            NameCandidate(id: "c-annika", givenName: "Annika", familyName: "Berg", nickname: "", displayName: "Annika Berg"),
        ]
    }

    private func result(names: [String], commitments: [ExtractedCommitment] = []) -> ExtractionResult {
        ExtractionResult(
            people: names.map { ExtractedPerson(name: $0, interacted: true, channelGuess: .inPerson, lifeEvent: nil) },
            commitments: commitments
        )
    }

    @Test func existingPersonBeatsContactWithSameName() {
        let outcome = ExtractionResolver.resolveName("Julia", persons: persons, contacts: contacts)
        #expect(outcome == .person(juliaID), "Julia is both a Person and a contact — the Person wins")
    }

    @Test func ambiguousPersonsAskInsteadOfGuessing() {
        let outcome = ExtractionResolver.resolveName("Max", persons: persons, contacts: contacts)
        guard case .ambiguousPersons(let ids) = outcome else {
            Issue.record("expected ambiguity, got \(outcome)")
            return
        }
        #expect(Set(ids) == [maxAID, maxBID])
    }

    @Test func familyInitialDisambiguates() {
        let outcome = ExtractionResolver.resolveName("Max W", persons: persons, contacts: contacts)
        #expect(outcome == .person(maxAID))
    }

    @Test func contactOnlyNameOffersLinkedCreation() {
        let outcome = ExtractionResolver.resolveName("Anna", persons: persons, contacts: contacts)
        guard case .contact(let candidate) = outcome else {
            Issue.record("expected contact, got \(outcome)")
            return
        }
        #expect(candidate.id == "c-anna")
    }

    @Test func unknownNameOffersUnlinkedCreation() {
        let outcome = ExtractionResolver.resolveName("Zebediah", persons: persons, contacts: contacts)
        #expect(outcome == .unknown)
    }

    @Test func diacriticsFoldDuringResolution() {
        let persons = [PersonRef(id: juliaID, displayName: "Jörg Müller")]
        let outcome = ExtractionResolver.resolveName("Jorg Muller", persons: persons, contacts: [])
        #expect(outcome == .person(juliaID))
    }

    @Test func duplicateExtractedNamesCollapse() {
        let suggestions = ExtractionResolver.resolve(
            result(names: ["Julia", "julia", "JULIA "]),
            entryID: UUID(),
            persons: persons,
            contacts: contacts
        )
        #expect(suggestions.mentions.count == 1)
    }

    @Test func emptyAndWhitespaceNamesAreDropped() {
        let suggestions = ExtractionResolver.resolve(
            result(names: ["", "   ", "Julia"]),
            entryID: UUID(),
            persons: persons,
            contacts: contacts
        )
        #expect(suggestions.mentions.count == 1)
    }

    @Test func commitmentsResolveTheirPerson() {
        let suggestions = ExtractionResolver.resolve(
            result(names: [], commitments: [
                ExtractedCommitment(text: "send the book", personName: "Julia"),
                ExtractedCommitment(text: "book the court", personName: nil),
            ]),
            entryID: UUID(),
            persons: persons,
            contacts: contacts
        )
        #expect(suggestions.commitments.count == 2)
        #expect(suggestions.commitments[0].personOutcome == .person(juliaID))
        #expect(suggestions.commitments[1].personOutcome == nil)
    }

    @Test func lifeEventAndChannelSurviveResolution() {
        let extraction = ExtractionResult(people: [
            ExtractedPerson(name: "Julia", interacted: true, channelGuess: .call, lifeEvent: "got the Bain offer")
        ])
        let suggestions = ExtractionResolver.resolve(extraction, entryID: UUID(), persons: persons, contacts: contacts)
        #expect(suggestions.mentions.first?.channelGuess == .call)
        #expect(suggestions.mentions.first?.lifeEvent == "got the Bain offer")
        #expect(suggestions.mentions.first?.interacted == true)
    }
}
