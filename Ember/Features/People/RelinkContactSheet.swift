// RelinkContactSheet.swift

import SwiftData
import SwiftUI

/// Contact deletion/merge is a normal state: this sheet re-links an unlinked
/// Person to a contact, restoring live name/photo/birthday resolution.
struct RelinkContactSheet: View {
    let person: Person
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var results: [ResolvedContact] = []

    var body: some View {
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
            .searchable(text: $searchText, prompt: String(localized: "Search contacts"))
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
        }
    }

    private func link(_ contact: ResolvedContact) {
        person.contactID = contact.id
        if !contact.displayName.isEmpty {
            person.displayNameCache = contact.displayName
        }
        try? modelContext.save()
        dismiss()
    }
}
