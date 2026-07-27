// PendingEntryCard.swift

import SwiftData
import SwiftUI

/// A saved entry awaiting review: who was mentioned, and did you actually
/// see or talk to them? Fully skippable — the entry is already saved.
/// (M4 replaces the manual picker with AI-suggested chips; this manual sheet
/// stays as the fallback for model-unavailable states.)
struct PendingEntryCard: View {
    let entry: Entry
    @Environment(\.modelContext) private var modelContext
    @State private var showReview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(entry.previewLine)
                .lineLimit(2)
            HStack {
                Text(entry.date, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "Skip")) {
                    entry.extractionState = .skipped
                    try? modelContext.save()
                }
                .buttonStyle(.bordered)
                Button(String(localized: "Review")) {
                    showReview = true
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
        .sheet(isPresented: $showReview) {
            MentionReviewSheet(entry: entry)
        }
    }
}

/// Manual mention selection — the behaviour port of v1's ContactSelectorView:
/// pick who's mentioned, optionally log it as a real interaction in the same step.
struct MentionReviewSheet: View {
    let entry: Entry
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Person.displayNameCache) private var people: [Person]
    @State private var selectedIDs: Set<UUID> = []
    @State private var alsoLogInteraction = false
    @State private var channel: Channel = .inPerson
    @State private var searchText = ""

    private var filteredPeople: [Person] {
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
                Section(String(localized: "Mentioned")) {
                    ForEach(filteredPeople) { person in
                        Button {
                            toggle(person.id)
                        } label: {
                            HStack {
                                Text(person.displayNameCache)
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
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func saveReview() {
        let selected = people.filter { selectedIDs.contains($0.id) }
        entry.mentions = selected
        if alsoLogInteraction {
            for person in selected {
                modelContext.insert(Interaction(
                    person: person,
                    date: entry.date,
                    channel: channel,
                    sourceEntryID: entry.id
                ))
            }
        }
        entry.extractionState = .reviewed
        try? modelContext.save()
        dismiss()
    }
}
