// KeepInTouchTests.swift

import Foundation
import SwiftData
import Testing
@testable import Ember

@Suite("Keep in touch choice")
struct KeepInTouchTests {
    @Test(arguments: CadenceTier.allCases)
    func nonPartnerMapsToItsTier(tier: CadenceTier) {
        let choice = KeepInTouch(tier: tier, isPartner: false)
        #expect(choice.tier == tier)
        #expect(!choice.isPartner)
    }

    @Test(arguments: CadenceTier.allCases)
    func partnerWinsOverAnyTier(tier: CadenceTier) {
        let choice = KeepInTouch(tier: tier, isPartner: true)
        #expect(choice == .partner)
        #expect(choice.tier == nil, "partner keeps whatever tier is stored")
    }

    @Test func everyChoiceRoundTrips() throws {
        for choice in KeepInTouch.allCases where !choice.isPartner {
            let tier = try #require(choice.tier)
            #expect(KeepInTouch(tier: tier, isPartner: false) == choice)
        }
    }

    @Test func addingChoicesLeaveOutPaused() {
        #expect(!KeepInTouch.addingChoices.contains(.paused))
        #expect(KeepInTouch.addingChoices.contains(.partner))
    }

    @Test func partnerLikeRelationsAreTheTwoDuplicates() {
        #expect(RelationKind.allCases.filter(\.isPartnerLike) == [.spouse, .partner])
    }
}

@MainActor
@Suite("Keep in touch assignment")
struct KeepInTouchAssignmentTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    @Test func choosingPartnerMovesTheFlag() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let julia = Person(displayNameCache: "Julia", tier: .close, isPartnerMode: true)
        let anna = Person(displayNameCache: "Anna", tier: .orbit)
        context.insert(julia)
        context.insert(anna)
        try context.save()

        KeepInTouchAssignment.apply(.partner, to: anna, context: context)

        #expect(anna.isPartnerMode)
        #expect(!julia.isPartnerMode, "one partner at a time")
        #expect(anna.tier == .orbit, "partner keeps the stored tier")
        #expect(julia.keepInTouch == .close, "the old partner falls back to their tier")
    }

    @Test func choosingATierClearsPartnerAndSetsTier() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let julia = Person(displayNameCache: "Julia", tier: .regular, isPartnerMode: true)
        context.insert(julia)
        try context.save()

        KeepInTouchAssignment.apply(.paused, to: julia, context: context)

        #expect(!julia.isPartnerMode)
        #expect(julia.tier == .paused)
        #expect(KeepInTouchAssignment.currentPartner(context: context) == nil)
    }

    @Test func insertingAPartnerDraftMovesTheFlagFromAnExistingPerson() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let julia = Person(displayNameCache: "Julia", tier: .close, isPartnerMode: true)
        context.insert(julia)
        try context.save()

        var tom = PersonDraft(unlinkedName: "Tom")
        tom.isPartner = true
        var anna = PersonDraft(unlinkedName: "Anna")
        anna.tier = .orbit
        KeepInTouchAssignment.insert([tom, anna], context: context)

        let people = try context.fetch(FetchDescriptor<Person>())
        #expect(people.count == 3)
        #expect(people.filter(\.isPartnerMode).map(\.displayNameCache) == ["Tom"])
        #expect(people.first { $0.displayNameCache == "Anna" }?.keepInTouch == .orbit)
        #expect(people.first { $0.displayNameCache == "Tom" }?.contactID == nil, "by-name drafts stay unlinked")
    }
}
