// DraftFallbackTests.swift

import Foundation
import SwiftData
import Testing
@testable import Ember

private struct FakeDraftProvider: DraftProviding {
    let fixed: String?
    func draft(for context: DraftContext) async -> String? { fixed }
}

@Suite("Draft fallback & sanitizer")
struct DraftFallbackTests {
    private func candidate() -> NudgeCandidate {
        let input = ScoringInput(
            personID: UUID(),
            displayName: "Anna",
            tier: .close,
            isPartner: false,
            daysSinceLastInteraction: 30,
            daysSinceCreated: 100,
            daysUntilBirthday: nil,
            openCommitmentCount: 0,
            daysSinceLastNudgeEvent: nil,
            lastInteractionNote: "coffee",
            lastInteractionChannel: .inPerson
        )
        return NudgeCandidate(input: input, score: 2.0, reasons: [.beenAWhile])
    }

    // MARK: Notification body composition

    @Test func nilDraftShipsContextOnly() {
        let withNil = NudgeCopy.notificationBody(for: candidate(), draft: nil)
        #expect(withNil == NudgeCopy.notificationBody(for: candidate()))
        #expect(!withNil.contains("“"))
    }

    @Test func draftIsAppendedInQuotes() {
        let body = NudgeCopy.notificationBody(for: candidate(), draft: "Hey! How was the lake?")
        #expect(body.contains("“Hey! How was the lake?”"))
        #expect(body.contains("coffee"), "context stays even with a draft")
    }

    @Test func emptyDraftBehavesLikeNil() {
        let body = NudgeCopy.notificationBody(for: candidate(), draft: "")
        #expect(!body.contains("“"))
    }

    // MARK: Engine wiring degrades gracefully

    @Test func engineWithNilProviderStillNudges() async throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let person = Person(displayNameCache: "Anna", tier: .close)
        context.insert(person)
        context.insert(Interaction(person: person, date: .now.addingTimeInterval(-30 * 86_400), channel: .inPerson))
        try context.save()

        let engine = NudgeEngine(container: container, contacts: ContactService())
        await engine.setDraftProvider(FakeDraftProvider(fixed: nil))
        await engine.evaluate()

        let logs = try ModelContext(container).fetch(FetchDescriptor<NudgeLog>())
        #expect(logs.count == 1, "a failing draft provider must never block the nudge")
    }

    // MARK: Sanitizer — the tone guard for AI output

    @Test func sanitizerPassesWarmSpecificDrafts() {
        let draft = "Hey Anna! How did the Bain interview go? Been thinking about you."
        #expect(DraftSanitizer.sanitize(draft) == draft)
    }

    @Test func sanitizerUnwrapsQuotes() {
        #expect(DraftSanitizer.sanitize("\"Hey! How's the new flat?\"") == "Hey! How's the new flat?")
        #expect(DraftSanitizer.sanitize("“Hey there”") == "Hey there")
    }

    @Test func sanitizerRejectsDayCounts() {
        #expect(DraftSanitizer.sanitize("Wow, 94 days since we talked!") == nil)
        #expect(DraftSanitizer.sanitize("It's been 3 weeks — sorry!") == nil)
    }

    @Test func sanitizerRejectsGuiltFraming() {
        #expect(DraftSanitizer.sanitize("We spoke so long ago.") == nil)
        #expect(DraftSanitizer.sanitize("It's been too long!") == nil)
        #expect(DraftSanitizer.sanitize("We haven't talked in forever.") == nil)
        #expect(DraftSanitizer.sanitize("Sorry for not reaching out.") == nil)
        #expect(DraftSanitizer.sanitize("Long time no see!") == nil)
    }

    @Test func sanitizerRejectsEmptyAndOversized() {
        #expect(DraftSanitizer.sanitize("") == nil)
        #expect(DraftSanitizer.sanitize("   \n") == nil)
        #expect(DraftSanitizer.sanitize(String(repeating: "hi ", count: 200)) == nil)
    }

    // MARK: DraftContext mapping

    @Test func draftContextOnlyCarriesInWindowBirthdays() {
        var input = ScoringInput(
            personID: UUID(),
            displayName: "Anna",
            tier: .close,
            isPartner: false,
            daysSinceLastInteraction: 30,
            daysSinceCreated: 100,
            daysUntilBirthday: 120,
            openCommitmentCount: 0,
            daysSinceLastNudgeEvent: nil
        )
        #expect(DraftContext(from: input).daysUntilBirthday == nil, "far-off birthdays don't belong in a draft")
        input.daysUntilBirthday = 3
        #expect(DraftContext(from: input).daysUntilBirthday == 3)
    }
}
