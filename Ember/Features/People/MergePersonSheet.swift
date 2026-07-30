// MergePersonSheet.swift

import SwiftData
import SwiftUI

/// Picks the surviving Person for a merge — the cleanup path for duplicates
/// (e.g. an Ember-only person later linked to an already-imported contact).
/// Everything moves to the survivor; the merged person is deleted.
struct MergePersonSheet: View {
    let source: Person
    /// Called after a completed merge, so the presenting detail view can
    /// dismiss itself — its person no longer exists.
    let onFinished: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Person.displayNameCache) private var people: [Person]
    @State private var searchText = ""
    @State private var mergeTarget: Person?

    private var candidates: [Person] {
        let others = people.filter { !$0.isPlaceholder && $0.id != source.id }
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return others }
        return others.filter {
            NameMatcher.matches(
                NameCandidate(id: "", givenName: "", familyName: "", nickname: "", displayName: $0.displayNameCache),
                query: trimmed
            )
        }
    }

    var body: some View {
        if source.isDeleted || source.modelContext == nil {
            // Merge completed — the source is gone; render nothing while the
            // sheet dismisses (attribute access on a detached @Model crashes).
            Color.clear
        } else {
            pickerList
        }
    }

    private var pickerList: some View {
        NavigationStack {
            List(candidates) { person in
                Button {
                    mergeTarget = person
                } label: {
                    HStack(spacing: 12) {
                        PersonAvatarView(person: person, size: 36)
                        Text(person.displayNameCache)
                            .foregroundStyle(.primary)
                        Spacer()
                        TierBadge(tier: person.tier)
                    }
                }
            }
            .overlay {
                if candidates.isEmpty {
                    EmptyStateView(
                        systemImage: "person.2",
                        title: String(localized: "No one to merge into"),
                        message: String(localized: "Try another spelling — or go back and remove them instead.")
                    )
                }
            }
            .searchable(text: $searchText, prompt: String(localized: "Search people"))
            .emberCanvas()
            .navigationTitle(String(localized: "Merge into…"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
            .alert(
                String(localized: "Merge \(source.displayNameCache) into \(mergeTarget?.displayNameCache ?? "")?"),
                isPresented: Binding(
                    get: { mergeTarget != nil },
                    set: { if !$0 { mergeTarget = nil } }
                )
            ) {
                Button(String(localized: "Merge")) {
                    guard let target = mergeTarget else { return }
                    merge(into: target)
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "Their journal mentions, interactions, commitments, ideas, and dates move over. \(mergeTarget?.displayNameCache ?? "") keeps their own name and cadence."))
            }
        }
    }

    private func merge(into target: Person) {
        let sourceID = source.id
        let targetID = target.id
        PersonMerge.merge(source, into: target, context: modelContext)
        Task { await services.personRemoved(sourceID, mergedInto: targetID) }
        dismiss()
        onFinished()
    }
}
