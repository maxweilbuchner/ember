// RelinkContactSheet.swift

import SwiftData
import SwiftUI

/// Contact deletion/merge is a normal state: this sheet re-links an unlinked
/// Person to a contact, restoring live name/photo/birthday resolution.
struct RelinkContactSheet: View {
    let person: Person
    /// Called after a merge-on-conflict — the presenting detail view's person
    /// no longer exists, so it should dismiss itself.
    var onMerged: () -> Void = {}
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var results: [ResolvedContact] = []
    @State private var conflictingPerson: Person?

    var body: some View {
        if person.isDeleted || person.modelContext == nil {
            // Merge-on-conflict completed — this person is gone; render nothing
            // while the sheet dismisses (attribute access would crash).
            Color.clear
        } else {
            searchList
        }
    }

    private var searchList: some View {
        NavigationStack {
            List(results, id: \.id) { contact in
                Button {
                    link(contact)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.displayName)
                            .foregroundStyle(.primary)
                        if !contact.phoneNumbers.isEmpty {
                            Text(contact.phoneNumbers[0].number)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .overlay {
                if results.isEmpty {
                    EmptyStateView(
                        systemImage: "person.crop.circle.dashed",
                        title: searchText.isEmpty
                            ? String(localized: "No contacts to show")
                            : String(localized: "No matches"),
                        message: searchText.isEmpty
                            ? String(localized: "You can widen contact access in Settings, or link them another time.")
                            : String(localized: "Try another spelling — or link them another time.")
                    )
                }
            }
            .searchable(text: $searchText, prompt: String(localized: "Search contacts"))
            .emberCanvas()
            .navigationTitle(String(localized: "Link a contact"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
            .task(id: searchText) {
                results = await services.contacts.search(searchText)
            }
            .alert(
                String(localized: "Already in Ember"),
                isPresented: Binding(
                    get: { conflictingPerson != nil },
                    set: { if !$0 { conflictingPerson = nil } }
                )
            ) {
                Button(String(localized: "Merge")) {
                    guard let target = conflictingPerson else { return }
                    merge(into: target)
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "This contact already belongs to \(conflictingPerson?.displayNameCache ?? ""). Merge \(person.displayNameCache) into them instead of creating a double?"))
            }
        }
    }

    private func link(_ contact: ResolvedContact) {
        // Another Person already holding this contact means the human is
        // already in Ember — linking would create a double. Offer the merge.
        let all = (try? modelContext.fetch(FetchDescriptor<Person>())) ?? []
        if let existing = all.first(where: { $0.contactID == contact.id && $0.id != person.id }) {
            conflictingPerson = existing
            return
        }
        person.contactID = contact.id
        if !contact.displayName.isEmpty {
            person.displayNameCache = contact.displayName
        }
        try? modelContext.save()
        dismiss()
    }

    private func merge(into target: Person) {
        let sourceID = person.id
        let targetID = target.id
        PersonMerge.merge(person, into: target, context: modelContext)
        Task { await services.personRemoved(sourceID, mergedInto: targetID) }
        dismiss()
        onMerged()
    }
}
