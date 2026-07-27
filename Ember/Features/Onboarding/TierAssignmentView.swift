// TierAssignmentView.swift

import SwiftUI

/// Sort the picked people into cadence tiers and optionally mark one partner.
struct TierAssignmentView: View {
    @Binding var drafts: [PersonDraft]
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach($drafts) { $draft in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(draft.contact.displayName)
                                    .fontWeight(.medium)
                                Spacer()
                                Button {
                                    setPartner(draft.id, to: !draft.isPartner)
                                } label: {
                                    Image(systemName: draft.isPartner ? "heart.fill" : "heart")
                                        .foregroundStyle(draft.isPartner ? Color.accentColor : Color.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            Picker(String(localized: "Cadence"), selection: $draft.tier) {
                                Text(CadenceTier.close.title).tag(CadenceTier.close)
                                Text(CadenceTier.regular.title).tag(CadenceTier.regular)
                                Text(CadenceTier.orbit.title).tag(CadenceTier.orbit)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        .padding(.vertical, 4)
                    }
                } footer: {
                    Text(String(localized: "Close ≈ every couple of weeks · Regular ≈ every month or two · Orbit ≈ a few times a year. Tap ♥ for your partner — they're never nudged, only remembered."))
                }
            }

            Button {
                onContinue()
            } label: {
                Text(String(localized: "Continue"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
        }
        .navigationTitle(String(localized: "How close?"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func setPartner(_ draftID: String, to value: Bool) {
        for index in drafts.indices {
            drafts[index].isPartner = value && drafts[index].id == draftID
        }
    }
}
