// DraftService.swift

import Foundation
import FoundationModels

/// Generates the 1–2 sentence casual opener for a nudge. Degrades gracefully:
/// any failure or unavailable state returns nil and the nudge ships with context
/// only. Drafts are never auto-sent — they land in an editable field.
actor DraftService: DraftProviding {
    func draft(for context: DraftContext) async -> String? {
        guard ModelAvailability.current == .available else { return nil }

        let session = LanguageModelSession(instructions: """
        You write short, casual text-message openers to close friends.
        One or two sentences, warm and specific, the way people actually text.
        Never mention or hint at how long it has been since they were last in touch.
        No guilt, no apologies for silence, no sign-off, no name signature.
        Respond with the message text only.
        """)

        var parts = ["Write an opener to \(context.displayName)."]
        if let note = context.lastInteractionNotes.first, !note.isEmpty {
            parts.append("Last time they talked about: \(String(note.prefix(120))).")
        }
        if !context.openCommitments.isEmpty {
            parts.append("The writer promised: \(context.openCommitments.prefix(2).joined(separator: "; ")).")
        }
        if let days = context.daysUntilBirthday {
            parts.append(days == 0 ? "Today is their birthday." : "Their birthday is in \(days) days.")
        }

        guard let response = try? await session.respond(to: parts.joined(separator: " ")) else {
            return nil
        }
        return DraftSanitizer.sanitize(response.content)
    }
}
