// LiveModelSmokeTests.swift

import Foundation
import Testing
@testable import Ember

/// Live Foundation Models smoke test — exercises the real on-device model when
/// Apple Intelligence is available, and passes trivially (with a note) when not.
@Suite("Live model smoke", .serialized)
struct LiveModelSmokeTests {
    @Test(.timeLimit(.minutes(2))) func extractionProducesMappedSuggestions() async {
        guard ModelAvailability.current == .available else {
            print("Live smoke skipped: model \(ModelAvailability.current)")
            return
        }
        let service = ExtractionService()
        let result = await service.extract(
            entryText: "Coffee with Anna this morning — she got the Bain offer! I promised to send her my case prep notes.",
            candidateNames: ["Anna Lopez", "Julia Schmidt", "Max Weilbuchner"]
        )
        guard let result else {
            Issue.record("model available but extraction returned nil")
            return
        }
        print("Live extraction: \(result)")
        #expect(result.people.contains { $0.name.localizedCaseInsensitiveContains("anna") })
    }

    @Test(.timeLimit(.minutes(2))) func draftGeneratesAndPassesSanitizer() async {
        guard ModelAvailability.current == .available else { return }
        let service = DraftService()
        let draft = await service.draft(for: DraftContext(
            displayName: "Anna",
            lastInteractionNotes: ["she got the Bain offer"],
            openCommitments: ["send the case prep notes"]
        ))
        print("Live draft: \(draft ?? "<nil — sanitizer or generation declined>")")
        // nil is a legal outcome (sanitizer may reject); a non-empty pass must be clean.
        if let draft {
            #expect(!draft.isEmpty)
            #expect(DraftSanitizer.sanitize(draft) != nil)
        }
    }
}
