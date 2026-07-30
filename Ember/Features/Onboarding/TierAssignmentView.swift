// TierAssignmentView.swift

import SwiftUI

/// Sort the picked people into cadence tiers and optionally mark one partner.
struct TierAssignmentView: View {
    @Binding var drafts: [PersonDraft]
    /// Hides the partner heart (one partner only) when someone already holds it.
    var partnerAlreadyExists: Bool = false
    /// Optional caption above the continue button (onboarding progress line).
    var barCaption: String?
    var onContinue: () -> Void

    var body: some View {
        List {
            Section {
                    ForEach($drafts) { $draft in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(draft.contact.displayName)
                                    .fontWeight(.medium)
                                Spacer()
                                if !partnerAlreadyExists {
                                    Button {
                                        setPartner(draft.id, to: !draft.isPartner)
                                    } label: {
                                        Image(systemName: draft.isPartner ? "heart.fill" : "heart")
                                            .foregroundStyle(draft.isPartner ? Color.accentColor : Color.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(draft.isPartner
                                        ? String(localized: "Unmark as partner")
                                        : String(localized: "Mark as partner"))
                                }
                            }
                            Picker(String(localized: "Cadence"), selection: $draft.tier) {
                                Text(CadenceTier.close.title).tag(CadenceTier.close)
                                Text(CadenceTier.regular.title).tag(CadenceTier.regular)
                                Text(CadenceTier.orbit.title).tag(CadenceTier.orbit)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    .padding(.vertical, EmberTheme.spacingXS)
                }
            } footer: {
                Text(partnerAlreadyExists
                    ? String(localized: "Close ≈ every couple of weeks · Regular ≈ every month or two · Orbit ≈ a few times a year. You've already marked a partner — change that from their page.")
                    : String(localized: "Close ≈ every couple of weeks · Regular ≈ every month or two · Orbit ≈ a few times a year. Tap ♥ for your partner — they're never nudged, only remembered."))
            }
        }
        .safeAreaInset(edge: .bottom) {
            PinnedBottomBar {
                if let barCaption {
                    Text(barCaption)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                Button {
                    onContinue()
                } label: {
                    Text(String(localized: "Continue"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .emberCanvas()
        .navigationTitle(String(localized: "How close?"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func setPartner(_ draftID: String, to value: Bool) {
        for index in drafts.indices {
            drafts[index].isPartner = value && drafts[index].id == draftID
        }
    }
}
