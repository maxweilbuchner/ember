// ExtractionService.swift

import Foundation
import FoundationModels

/// Wraps Foundation Models guided generation. One short-lived session per
/// extraction (the context window is ~4k tokens — prompts stay small: entry text
/// truncated, candidate list capped). Output is always a suggestion, never a
/// silent write.
actor ExtractionService: ExtractionProviding {
    nonisolated static let maxCandidateNames = 40
    nonisolated static let maxEntryLength = 1500

    func extract(entryText: String, candidateNames: [String]) async -> ExtractionResult? {
        guard ModelAvailability.current == .available else { return nil }

        let names = candidateNames.prefix(Self.maxCandidateNames).joined(separator: ", ")
        let instructions = """
        You extract structured facts from one short personal journal entry.
        People the writer already knows: \(names).
        Match mentioned names against that list when possible, but keep the name exactly as written in the entry.
        Only extract what the entry explicitly says. Never invent people, events, or promises.
        """
        let session = LanguageModelSession(instructions: instructions)
        let text = String(entryText.prefix(Self.maxEntryLength))
        guard let response = try? await session.respond(to: text, generating: GenerableExtraction.self) else {
            return nil
        }
        return Self.map(response.content)
    }

    private nonisolated static func map(_ generated: GenerableExtraction) -> ExtractionResult {
        ExtractionResult(
            people: generated.people.map {
                ExtractedPerson(
                    name: $0.name,
                    interacted: $0.interacted,
                    channelGuess: $0.channel.channel,
                    lifeEvent: $0.lifeEvent?.isEmpty == false ? $0.lifeEvent : nil
                )
            },
            commitments: generated.commitments.map {
                ExtractedCommitment(
                    text: $0.text,
                    personName: $0.personName?.isEmpty == false ? $0.personName : nil
                )
            }
        )
    }
}

// MARK: Guided-generation types (private to this service; the app uses ExtractionResult)

@Generable
nonisolated struct GenerableExtraction {
    @Guide(description: "People mentioned by name in the entry, with their name exactly as written")
    var people: [GenerablePerson]

    @Guide(description: "Promises the writer made to someone, each as a short to-do like 'send Daniel the book'. Empty if none.")
    var commitments: [GenerableCommitment]
}

@Generable
nonisolated struct GenerablePerson {
    @Guide(description: "The name exactly as written in the entry")
    var name: String

    @Guide(description: "True only if the writer actually met, called, or messaged this person in this entry — not if they were merely mentioned")
    var interacted: Bool

    @Guide(description: "How they communicated, if they did")
    var channel: GenerableChannel

    @Guide(description: "A notable life event for this person mentioned in the entry (new job, exam, move, baby), or null")
    var lifeEvent: String?
}

@Generable
nonisolated enum GenerableChannel {
    case inPerson
    case call
    case message
    case unknown

    var channel: Channel {
        switch self {
        case .inPerson: .inPerson
        case .call: .call
        case .message: .message
        case .unknown: .other
        }
    }
}

@Generable
nonisolated struct GenerableCommitment {
    @Guide(description: "The promise as a short imperative phrase")
    var text: String

    @Guide(description: "Name of the person the promise is for, or null")
    var personName: String?
}
