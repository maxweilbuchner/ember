// AddPeopleSheet.swift

import SwiftData
import SwiftUI

/// Add more people after onboarding: same picker + keep-in-touch steps as
/// onboarding. People added by name only (not in Contacts) join the same
/// keep-in-touch step, so nobody skips it.
struct AddPeopleSheet: View {
    private enum Step {
        case pick
        case keepInTouch
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var existingPeople: [Person]
    @State private var step: Step = .pick
    @State private var drafts: [PersonDraft] = []
    @State private var unlinkedName = ""
    @State private var justAddedName: String?

    private var existingContactIDs: Set<String> {
        Set(existingPeople.compactMap(\.contactID))
    }

    var body: some View {
        NavigationStack {
            switch step {
            case .pick:
                PeoplePickerView(
                    drafts: $drafts,
                    excludedContactIDs: existingContactIDs,
                    continueTitle: String(localized: "Next"),
                    onContinue: {
                        if drafts.isEmpty {
                            dismiss()
                        } else {
                            step = .keepInTouch
                        }
                    },
                    barAccessory: {
                        VStack(spacing: EmberTheme.spacingS) {
                            HStack {
                                TextField(String(localized: "Or add someone by name only…"), text: $unlinkedName)
                                    .textFieldStyle(.roundedBorder)
                                Button(String(localized: "Add")) {
                                    addUnlinked()
                                }
                                .disabled(unlinkedName.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                            if let justAddedName {
                                Text(String(localized: "Added \(justAddedName) — pick more people or continue."))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .transition(.opacity)
                            }
                        }
                        .animation(EmberTheme.calm, value: justAddedName)
                    }
                )
                .onChange(of: unlinkedName) { _, newValue in
                    if !newValue.isEmpty {
                        justAddedName = nil
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel")) { dismiss() }
                    }
                }
            case .keepInTouch:
                KeepInTouchStep(
                    drafts: $drafts,
                    existingPartnerName: existingPeople.first(where: \.isPartnerMode)?.displayNameCache
                ) {
                    KeepInTouchAssignment.insert(drafts, context: modelContext)
                    dismiss()
                }
            }
        }
    }

    private func addUnlinked() {
        let name = unlinkedName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        // Held as a draft like any contact pick, so they get the same
        // keep-in-touch step — and in-progress selections survive.
        drafts.append(PersonDraft(unlinkedName: name))
        unlinkedName = ""
        justAddedName = name
    }
}
