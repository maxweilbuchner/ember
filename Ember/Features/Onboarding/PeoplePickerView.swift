// PeoplePickerView.swift

import SwiftUI

/// Search-and-select contacts to bring into Ember. Used by onboarding and by
/// the People tab's add sheet.
struct PeoplePickerView<BarAccessory: View>: View {
    @Binding var drafts: [PersonDraft]
    var excludedContactIDs: Set<String> = []
    var continueTitle: String = String(localized: "Continue")
    var onContinue: () -> Void
    /// Extra control rendered above the continue button in the bottom bar
    /// (AddPeopleSheet's add-by-name field).
    @ViewBuilder var barAccessory: () -> BarAccessory

    @Environment(AppServices.self) private var services
    @State private var searchText = ""
    @State private var contacts: [ResolvedContact] = []

    private var visibleContacts: [ResolvedContact] {
        contacts.filter { !excludedContactIDs.contains($0.id) }
    }

    var body: some View {
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
        .safeAreaInset(edge: .bottom) {
            PinnedBottomBar {
                barAccessory()
                Button {
                    onContinue()
                } label: {
                    Text(drafts.isEmpty ? String(localized: "Skip for now") : "\(continueTitle) (\(drafts.count))")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .searchable(text: $searchText, prompt: String(localized: "Search contacts"))
        .emberCanvas()
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

extension PeoplePickerView where BarAccessory == EmptyView {
    init(
        drafts: Binding<[PersonDraft]>,
        excludedContactIDs: Set<String> = [],
        continueTitle: String = String(localized: "Continue"),
        onContinue: @escaping () -> Void
    ) {
        self.init(
            drafts: drafts,
            excludedContactIDs: excludedContactIDs,
            continueTitle: continueTitle,
            onContinue: onContinue,
            barAccessory: { EmptyView() }
        )
    }
}
