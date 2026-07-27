// AddPeopleSheet.swift

import SwiftData
import SwiftUI

/// Add more people after onboarding: same picker + tier steps, or create an
/// unlinked person by name when they're not in Contacts.
struct AddPeopleSheet: View {
    private enum Step {
        case pick
        case tiers
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var existingPeople: [Person]
    @State private var step: Step = .pick
    @State private var drafts: [PersonDraft] = []
    @State private var unlinkedName = ""

    private var existingContactIDs: Set<String> {
        Set(existingPeople.compactMap(\.contactID))
    }

    var body: some View {
        NavigationStack {
            switch step {
            case .pick:
                VStack(spacing: 0) {
                    PeoplePickerView(
                        drafts: $drafts,
                        excludedContactIDs: existingContactIDs,
                        continueTitle: String(localized: "Next")
                    ) {
                        if drafts.isEmpty {
                            dismiss()
                        } else {
                            step = .tiers
                        }
                    }
                    HStack {
                        TextField(String(localized: "Or add someone by name only…"), text: $unlinkedName)
                            .textFieldStyle(.roundedBorder)
                        Button(String(localized: "Add")) {
                            addUnlinked()
                        }
                        .disabled(unlinkedName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding([.horizontal, .bottom])
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel")) { dismiss() }
                    }
                }
            case .tiers:
                TierAssignmentView(drafts: $drafts) {
                    saveDrafts()
                }
            }
        }
    }

    private func addUnlinked() {
        let name = unlinkedName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        modelContext.insert(Person(displayNameCache: name))
        try? modelContext.save()
        unlinkedName = ""
        dismiss()
    }

    private func saveDrafts() {
        let hasExistingPartner = existingPeople.contains(where: \.isPartnerMode)
        for draft in drafts {
            modelContext.insert(Person(
                contactID: draft.contact.id,
                displayNameCache: draft.contact.displayName,
                tier: draft.tier,
                isPartnerMode: draft.isPartner && !hasExistingPartner
            ))
        }
        try? modelContext.save()
        dismiss()
    }
}
