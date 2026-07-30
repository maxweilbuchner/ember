// ExtractionChipsView.swift

import SwiftData
import SwiftUI

/// The tags on a saved entry. People Ember already knows are tagged
/// automatically (filled chip, × to undo); anything that would create a Person,
/// or that is ambiguous, waits as an outline chip where one tap is one write.
/// No Apply step — every chip commits itself (spec §4.2).
struct ExtractionChipsView: View {
    let entry: Entry
    let suggestions: EntrySuggestions?

    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query private var allPeople: [Person]
    @State private var ambiguousPick: MentionSuggestion?
    @State private var writeCount = 0

    private var people: [Person] {
        allPeople.filter { !$0.isPlaceholder }
    }

    private var openMentions: [MentionSuggestion] {
        suggestions?.mentions ?? []
    }

    private var openCommitments: [CommitmentSuggestion] {
        suggestions?.commitments ?? []
    }

    private var hasAnything: Bool {
        !entry.mentions.isEmpty || !openMentions.isEmpty || !openCommitments.isEmpty
    }

    var body: some View {
        if hasAnything {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)],
                alignment: .leading,
                spacing: EmberTheme.spacingS
            ) {
                ForEach(entry.mentions) { person in
                    tagChip(person)
                }
                ForEach(openMentions) { mention in
                    suggestionChip(mention)
                }
                ForEach(openCommitments) { commitment in
                    commitmentChip(commitment)
                }
            }
            .animation(EmberTheme.calm, value: entry.mentions.map(\.id))
            .animation(EmberTheme.calm, value: openMentions.map(\.id))
            .sensoryFeedback(.selection, trigger: writeCount)
            .confirmationDialog(
                String(localized: "Who is \"\(ambiguousPick?.name ?? "")\"?"),
                isPresented: Binding(get: { ambiguousPick != nil }, set: { if !$0 { ambiguousPick = nil } }),
                titleVisibility: .visible
            ) {
                if let pick = ambiguousPick {
                    ForEach(options(for: pick), id: \.id) { option in
                        Button(option.displayName) {
                            commit(pick, pickedPersonID: option.id)
                            ambiguousPick = nil
                        }
                    }
                }
            }
        }
    }

    // MARK: Chips

    /// An applied tag — tapping the × undoes it (and the interaction it logged).
    private func tagChip(_ person: Person) -> some View {
        Button {
            MentionApplier.untag(person, from: entry, context: modelContext)
            writeCount += 1
        } label: {
            HStack(spacing: 4) {
                if person.isPartnerMode {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                }
                Text(NameMatcher.compactName(person.displayNameCache))
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .tint(Color.accentColor)
        .controlSize(.small)
        .accessibilityLabel(String(localized: "Remove tag \(person.displayNameCache)"))
    }

    private func suggestionChip(_ mention: MentionSuggestion) -> some View {
        Button {
            tap(mention)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: chipIcon(for: mention.outcome))
                Text(chipLabel(for: mention))
                    .lineLimit(1)
            }
            .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .tint(Color.secondary)
        .controlSize(.small)
    }

    private func commitmentChip(_ commitment: CommitmentSuggestion) -> some View {
        Button {
            MentionApplier.apply(commitment, to: entry, people: people, context: modelContext)
            clear(commitment)
            writeCount += 1
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "checklist")
                Text(commitment.text)
                    .lineLimit(1)
            }
            .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .tint(Color.secondary)
        .controlSize(.small)
    }

    private func chipIcon(for outcome: NameResolutionOutcome) -> String {
        switch outcome {
        case .person: "person.crop.circle"
        case .contact: "person.crop.circle.badge.plus"
        case .ambiguousPersons, .ambiguousContacts: "questionmark.circle"
        case .unknown: "sparkles"
        }
    }

    private func chipLabel(for mention: MentionSuggestion) -> String {
        switch mention.outcome {
        case .unknown, .contact: String(localized: "Add \"\(mention.name)\"?")
        default: mention.name
        }
    }

    // MARK: Actions

    private func tap(_ mention: MentionSuggestion) {
        switch mention.outcome {
        case .person, .contact, .unknown:
            commit(mention, pickedPersonID: nil)
        case .ambiguousPersons, .ambiguousContacts:
            ambiguousPick = mention
        }
    }

    private func commit(_ mention: MentionSuggestion, pickedPersonID: UUID?) {
        MentionApplier.apply(
            mention,
            pickedPersonID: pickedPersonID,
            to: entry,
            people: people,
            context: modelContext
        )
        clear(mention)
        writeCount += 1
    }

    /// A suggestion that became data stops being a suggestion.
    private func clear(_ mention: MentionSuggestion) {
        guard var current = services.entrySuggestions[entry.id] else { return }
        current.mentions.removeAll { $0.id == mention.id }
        services.entrySuggestions[entry.id] = current.isEmpty ? nil : current
    }

    private func clear(_ commitment: CommitmentSuggestion) {
        guard var current = services.entrySuggestions[entry.id] else { return }
        current.commitments.removeAll { $0.id == commitment.id }
        services.entrySuggestions[entry.id] = current.isEmpty ? nil : current
    }

    private func options(for mention: MentionSuggestion) -> [(id: UUID, displayName: String)] {
        switch mention.outcome {
        case .ambiguousPersons(let ids):
            return people.filter { ids.contains($0.id) }.map { ($0.id, $0.displayNameCache) }
        case .ambiguousContacts(let candidates):
            return candidates.map { (MentionApplier.deterministicUUID(for: $0.id), $0.displayName) }
        default:
            return []
        }
    }
}
