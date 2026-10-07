// KeepInTouchStep.swift

import SwiftUI

/// Sort freshly picked people: how often to keep in touch, and optionally who
/// your partner is — one picker per person, the same one their page uses.
struct KeepInTouchStep: View {
    @Binding var drafts: [PersonDraft]
    /// Whoever already holds partner mode (Add People only). Picking Partner
    /// here still works — it moves the ♥, exactly as on a person's page.
    var existingPartnerName: String?
    /// Optional caption above the continue button (onboarding progress line).
    var barCaption: String?
    var onContinue: () -> Void

    var body: some View {
        List {
            Section {
                ForEach(drafts) { draft in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text(draft.displayName.isEmpty ? String(localized: "No name") : draft.displayName)
                                .fontWeight(.medium)
                            if draft.isPartner {
                                Image(systemName: "heart.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        KeepInTouchPicker(
                            selection: binding(for: draft.id),
                            choices: KeepInTouch.addingChoices,
                            segmented: true
                        )
                    }
                    .padding(.vertical, EmberTheme.spacingXS)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Close ≈ every couple of weeks · Regular ≈ every month or two · Orbit ≈ a few times a year. Partner is never nudged, only remembered. Change any of this later on their page."))
                    if let existingPartnerName, !drafts.contains(where: \.isPartner) {
                        Text(String(localized: "\(existingPartnerName) is your partner in Ember — choosing Partner here moves it."))
                    }
                }
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

    /// One partner at a time: choosing Partner for one draft clears it from
    /// the rest; the stored tier is kept so switching back restores it.
    private func binding(for draftID: String) -> Binding<KeepInTouch> {
        Binding(
            get: { drafts.first(where: { $0.id == draftID })?.keepInTouch ?? .regular },
            set: { choice in
                for index in drafts.indices {
                    if drafts[index].id == draftID {
                        drafts[index].isPartner = choice.isPartner
                        if let tier = choice.tier {
                            drafts[index].tier = tier
                        }
                    } else if choice.isPartner {
                        drafts[index].isPartner = false
                    }
                }
            }
        )
    }
}
