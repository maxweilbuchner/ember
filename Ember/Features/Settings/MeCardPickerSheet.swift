// MeCardPickerSheet.swift

import SwiftUI

/// Picks which contact card is the user's own — iOS has no public me-card API,
/// so Ember asks once here. The card's relationship labels ("mother", "spouse")
/// become relation chips on people's profiles.
struct MeCardPickerSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var results: [ResolvedContact] = []

    var body: some View {
        NavigationStack {
            List {
                if MeCard.contactID != nil && searchText.isEmpty {
                    Button(String(localized: "Clear selection"), role: .destructive) {
                        MeCard.contactID = nil
                        dismiss()
                    }
                }
                ForEach(results, id: \.id) { contact in
                    Button {
                        MeCard.contactID = contact.id
                        dismiss()
                    } label: {
                        HStack {
                            Text(contact.displayName)
                                .foregroundStyle(.primary)
                            if contact.id == MeCard.contactID {
                                Spacer()
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
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
                        message: String(localized: "Pick your own card so Ember can read the relationships on it.")
                    )
                }
            }
            .searchable(text: $searchText, prompt: String(localized: "Search contacts"))
            .emberCanvas()
            .navigationTitle(String(localized: "Your card"))
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
}
