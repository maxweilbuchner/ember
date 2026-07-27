// PeoplePickerView.swift

import SwiftUI

/// Search-and-select contacts to bring into Ember. Used by onboarding and by
/// the People tab's add sheet.
struct PeoplePickerView: View {
    @Binding var drafts: [PersonDraft]
    var excludedContactIDs: Set<String> = []
    var continueTitle: String = String(localized: "Continue")
    var onContinue: () -> Void

    @Environment(AppServices.self) private var services
    @State private var searchText = ""
    @State private var contacts: [ResolvedContact] = []

    private var visibleContacts: [ResolvedContact] {
        contacts.filter { !excludedContactIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            List(visibleContacts, id: \.id) { contact in
                Button {
                    toggle(contact)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.displayName.isEmpty ? String(localized: "No name") : contact.displayName)
                                .foregroundStyle(.primary)
                            if !contact.phoneNumbers.isEmpty {
                                Text(contact.phoneNumbers[0].number)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if drafts.contains(where: { $0.contact.id == contact.id }) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        } else {
                            Image(systemName: "circle")
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .overlay {
                if contacts.isEmpty {
                    EmptyStateView(
                        systemImage: "person.crop.circle.dashed",
                        title: String(localized: "No contacts to show"),
                        message: String(localized: "You can widen contact access in Settings, or add people later.")
                    )
                }
            }

            Button {
                onContinue()
            } label: {
                Text(drafts.isEmpty ? String(localized: "Skip for now") : "\(continueTitle) (\(drafts.count))")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
        }
        .searchable(text: $searchText, prompt: String(localized: "Search contacts"))
        .navigationTitle(String(localized: "Pick your people"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: searchText) {
            contacts = await services.contacts.search(searchText)
        }
    }

    private func toggle(_ contact: ResolvedContact) {
        if let index = drafts.firstIndex(where: { $0.contact.id == contact.id }) {
            drafts.remove(at: index)
        } else {
            drafts.append(PersonDraft(contact: contact))
        }
    }
}
