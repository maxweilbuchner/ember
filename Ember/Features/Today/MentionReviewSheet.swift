// MentionReviewSheet.swift

import SwiftData
import SwiftUI

/// Manual mention selection — the behaviour port of v1's ContactSelectorView:
/// pick who's mentioned, optionally log it as a real interaction in the same step.
struct MentionReviewSheet: View {
    let entry: Entry
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Person.displayNameCache) private var people: [Person]
    @State private var selectedIDs: Set<UUID> = []
    @State private var originalIDs: Set<UUID> = []
    @State private var showReplaceOffer = false
    @State private var alsoLogInteraction = false
    @State private var channel: Channel = .inPerson
    @State private var searchText = ""

    private var filteredPeople: [Person] {
        let people = people.filter { !$0.isPlaceholder }
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return people }
        return people.filter {
            NameMatcher.matches(
                NameCandidate(id: "", givenName: "", familyName: "", nickname: "", displayName: $0.displayNameCache),
                query: trimmed
            )
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(entry.text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
                // Anonymized tombstone mentions can be kept or removed here —
                // they never appear in the normal pick list below.
                if entry.mentions.contains(where: \.isPlaceholder) {
                    Section {
                        ForEach(entry.mentions.filter(\.isPlaceholder)) { placeholder in
                            Button {
                                toggle(placeholder.id)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(placeholder.displayNameCache)
                                            .foregroundStyle(.primary)
                                        Text(String(localized: "Anonymized mention — can only be removed"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedIDs.contains(placeholder.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }
                Section(String(localized: "Mentioned")) {
                    ForEach(filteredPeople) { person in
                        Button {
                            toggle(person.id)
                        } label: {
                            HStack {
                                HStack(spacing: 4) {
                                    Text(person.displayNameCache)
                                    if person.isPartnerMode {
                                        Image(systemName: "heart.fill")
                                            .font(.caption)
                                    }
                                }
                                .foregroundStyle(.primary)
                                Spacer()
                                if selectedIDs.contains(person.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
                if !selectedIDs.isEmpty {
                    Section {
                        Toggle(String(localized: "We saw each other or talked"), isOn: $alsoLogInteraction)
                        if alsoLogInteraction {
                            Picker(String(localized: "How"), selection: $channel) {
                                ForEach(Channel.allCases, id: \.self) { channel in
                                    Text(channel.title).tag(channel)
                                }
                            }
                        }
                    } footer: {
                        Text(String(localized: "This logs an interaction — the signal Ember uses to know you're in touch."))
                    }
                }
            }
            .searchable(text: $searchText, prompt: String(localized: "Find a person"))
            .emberCanvas()
            .navigationTitle(String(localized: "Who was mentioned?"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { saveReview() }
                }
            }
            .onAppear {
                selectedIDs = Set(entry.mentions.map(\.id))
                originalIDs = selectedIDs
            }
            .alert(String(localized: "Also remove Someone?"), isPresented: $showReplaceOffer) {
                Button(String(localized: "Remove"), role: .destructive) {
                    commit(removingPlaceholders: true)
                }
                Button(String(localized: "Keep Someone"), role: .cancel) {
                    commit(removingPlaceholders: false)
                }
            } message: {
                Text(replaceOfferMessage)
            }
        }
    }

    private var replaceOfferMessage: String {
        let addedNames = people
            .filter { selectedIDs.subtracting(originalIDs).contains($0.id) }
            .map(\.displayNameCache)
        let names = addedNames.isEmpty
            ? String(localized: "someone new")
            : addedNames.joined(separator: ", ")
        return String(localized: "You added \(names). If that anonymized mention was them, it's no longer needed. Your journal text isn't changed.")
    }

    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func saveReview() {
        // Someone new was ticked while an anonymized mention is still selected:
        // offer to drop the tombstone once, then commit either way.
        let newlyAdded = selectedIDs.subtracting(originalIDs)
        let placeholderStillSelected = entry.mentions.contains { $0.isPlaceholder && selectedIDs.contains($0.id) }
        if !newlyAdded.isEmpty && placeholderStillSelected {
            showReplaceOffer = true
            return
        }
        commit(removingPlaceholders: false)
    }

    private func commit(removingPlaceholders: Bool) {
        if removingPlaceholders {
            for placeholder in entry.mentions where placeholder.isPlaceholder {
                selectedIDs.remove(placeholder.id)
            }
        }
        let selected = people.filter { selectedIDs.contains($0.id) }
        entry.mentions = selected
        if alsoLogInteraction {
            for person in selected where !person.isPlaceholder {
                modelContext.insert(Interaction(
                    person: person,
                    date: entry.date,
                    channel: channel,
                    sourceEntryID: entry.id
                ))
            }
        }
        entry.extractionState = .reviewed
        PersonMerge.deleteOrphanedPlaceholders(context: modelContext)
        try? modelContext.save()
        dismiss()
    }
}
