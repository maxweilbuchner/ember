// ExtractionChipsView.swift

import SwiftData
import SwiftUI

/// AI suggestions rendered as one-tap confirmation chips under a pending entry:
/// mentions (with create-person offers for contacts and unknowns), an
/// interaction toggle, and commitments. Nothing is written until a chip is
/// confirmed and Apply is tapped — suggestions, never silent writes.
struct ExtractionChipsView: View {
    let entry: Entry
    let suggestions: EntrySuggestions

    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query private var allPeople: [Person]
    @State private var confirmedMentions: Set<String> = []
    @State private var confirmedCommitments: Set<String> = []
    @State private var pickedResolutions: [String: UUID] = [:]
    @State private var ambiguousPick: MentionSuggestion?
    @State private var logInteractions = true

    private var hasInteractionSuggestion: Bool {
        suggestions.mentions.contains(where: \.interacted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !suggestions.mentions.isEmpty {
                chipRow(String(localized: "Mentioned")) {
                    ForEach(suggestions.mentions) { mention in
                        mentionChip(mention)
                    }
                }
            }
            if !suggestions.commitments.isEmpty {
                chipRow(String(localized: "Commitments")) {
                    ForEach(suggestions.commitments) { commitment in
                        commitmentChip(commitment)
                    }
                }
            }
            if hasInteractionSuggestion && !confirmedMentions.isEmpty {
                Toggle(isOn: $logInteractions) {
                    Text(String(localized: "Log as interaction"))
                        .font(.subheadline)
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            if !confirmedMentions.isEmpty || !confirmedCommitments.isEmpty {
                Button(String(localized: "Apply")) {
                    apply()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .confirmationDialog(
            String(localized: "Who is \"\(ambiguousPick?.name ?? "")\"?"),
            isPresented: Binding(get: { ambiguousPick != nil }, set: { if !$0 { ambiguousPick = nil } }),
            titleVisibility: .visible
        ) {
            if let pick = ambiguousPick {
                ForEach(options(for: pick), id: \.id) { option in
                    Button(option.displayName) {
                        pickedResolutions[pick.name] = option.id
                        confirmedMentions.insert(pick.name)
                        ambiguousPick = nil
                    }
                }
            }
        }
    }

    // MARK: Chips

    private func chipRow(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 6) {
                content()
            }
        }
    }

    private func mentionChip(_ mention: MentionSuggestion) -> some View {
        let isConfirmed = confirmedMentions.contains(mention.name)
        return Button {
            tapMention(mention)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isConfirmed ? "checkmark.circle.fill" : chipIcon(for: mention.outcome))
                Text(chipLabel(for: mention))
                    .lineLimit(1)
            }
            .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .tint(isConfirmed ? Color.accentColor : Color.secondary)
        .controlSize(.small)
    }

    private func commitmentChip(_ commitment: CommitmentSuggestion) -> some View {
        let isConfirmed = confirmedCommitments.contains(commitment.text)
        return Button {
            if isConfirmed {
                confirmedCommitments.remove(commitment.text)
            } else {
                confirmedCommitments.insert(commitment.text)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isConfirmed ? "checkmark.circle.fill" : "plus.circle")
                Text(commitment.text)
                    .lineLimit(1)
            }
            .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .tint(isConfirmed ? Color.accentColor : Color.secondary)
        .controlSize(.small)
    }

    private func chipIcon(for outcome: NameResolutionOutcome) -> String {
        switch outcome {
        case .person: "circle"
        case .contact: "person.crop.circle.badge.plus"
        case .ambiguousPersons, .ambiguousContacts: "questionmark.circle"
        case .unknown: "sparkles"
        }
    }

    private func chipLabel(for mention: MentionSuggestion) -> String {
        switch mention.outcome {
        case .unknown: String(localized: "Add \"\(mention.name)\"?")
        default: mention.name
        }
    }

    // MARK: Actions

    private func tapMention(_ mention: MentionSuggestion) {
        if confirmedMentions.contains(mention.name) {
            confirmedMentions.remove(mention.name)
            return
        }
        switch mention.outcome {
        case .person, .contact, .unknown:
            confirmedMentions.insert(mention.name)
        case .ambiguousPersons, .ambiguousContacts:
            ambiguousPick = mention
        }
    }

    private func options(for mention: MentionSuggestion) -> [(id: UUID, displayName: String)] {
        switch mention.outcome {
        case .ambiguousPersons(let ids):
            return allPeople.filter { ids.contains($0.id) }.map { ($0.id, $0.displayNameCache) }
        case .ambiguousContacts(let candidates):
            // Materialise on pick: map each candidate through person creation lazily.
            return candidates.map { (deterministicUUID(for: $0.id), $0.displayName) }
        default:
            return []
        }
    }

    /// Stable placeholder IDs so ambiguous-contact options can round-trip through
    /// the picker before a Person exists.
    private func deterministicUUID(for contactID: String) -> UUID {
        var hasher = Hasher()
        hasher.combine(contactID)
        let seed = UInt64(bitPattern: Int64(hasher.finalize()))
        return UUID(uuidString: String(format: "%08X-0000-4000-8000-%012llX", UInt32(truncatingIfNeeded: seed), seed & 0xFFFF_FFFF_FFFF)) ?? UUID()
    }

    private func apply() {
        var mentionedPeople: [Person] = []

        for mention in suggestions.mentions where confirmedMentions.contains(mention.name) {
            if let person = materialisePerson(for: mention) {
                mentionedPeople.append(person)
            }
        }

        var mentions = entry.mentions
        for person in mentionedPeople where !mentions.contains(where: { $0.id == person.id }) {
            mentions.append(person)
        }
        entry.mentions = mentions

        if logInteractions {
            for mention in suggestions.mentions
            where mention.interacted && confirmedMentions.contains(mention.name) {
                guard let person = mentionedPeople.first(where: { matches($0, mention: mention) }) else { continue }
                modelContext.insert(Interaction(
                    person: person,
                    date: entry.date,
                    channel: mention.channelGuess,
                    note: mention.lifeEvent,
                    sourceEntryID: entry.id
                ))
            }
        }

        for commitment in suggestions.commitments where confirmedCommitments.contains(commitment.text) {
            let owner: Person?
            if case .person(let id) = commitment.personOutcome {
                owner = allPeople.first { $0.id == id } ?? mentionedPeople.first { $0.id == id }
            } else if let name = commitment.personName {
                owner = mentionedPeople.first { NameMatcher.fold($0.displayNameCache).hasPrefix(NameMatcher.fold(name)) }
            } else {
                owner = nil
            }
            modelContext.insert(Commitment(person: owner, text: commitment.text, sourceEntryID: entry.id))
        }

        entry.extractionState = .reviewed
        try? modelContext.save()
        services.entrySuggestions[entry.id] = nil
    }

    private func matches(_ person: Person, mention: MentionSuggestion) -> Bool {
        switch mention.outcome {
        case .person(let id):
            person.id == id || pickedResolutions[mention.name] == person.id
        case .ambiguousPersons:
            pickedResolutions[mention.name] == person.id
        default:
            NameMatcher.fold(person.displayNameCache).hasPrefix(NameMatcher.fold(mention.name))
                || person.displayNameCache == mention.name
        }
    }

    /// Turns a confirmed suggestion into a Person: existing, created-from-contact,
    /// or created-unlinked.
    private func materialisePerson(for mention: MentionSuggestion) -> Person? {
        switch mention.outcome {
        case .person(let id):
            return allPeople.first { $0.id == id }
        case .ambiguousPersons:
            guard let picked = pickedResolutions[mention.name] else { return nil }
            return allPeople.first { $0.id == picked }
        case .contact(let candidate):
            return findOrCreate(from: candidate)
        case .ambiguousContacts(let candidates):
            guard let picked = pickedResolutions[mention.name],
                  let candidate = candidates.first(where: { deterministicUUID(for: $0.id) == picked }) else { return nil }
            return findOrCreate(from: candidate)
        case .unknown:
            let person = Person(displayNameCache: mention.name)
            modelContext.insert(person)
            return person
        }
    }

    private func findOrCreate(from candidate: NameCandidate) -> Person {
        if let existing = allPeople.first(where: { $0.contactID == candidate.id }) {
            return existing
        }
        let person = Person(contactID: candidate.id, displayNameCache: candidate.displayName)
        modelContext.insert(person)
        return person
    }
}
