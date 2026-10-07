// NudgeCardView.swift

import SwiftData
import SwiftUI

/// A nudge on the Today tab: who, why (straight from the NudgeLog), and the
/// context worth opening with — then the same actions as the notification.
struct NudgeCardView: View {
    let log: NudgeLog
    let person: Person
    @Environment(AppServices.self) private var services
    @State private var actionCount = 0

    /// Spec §4.4: the nudge is the context, not just the name.
    private var context: String? {
        let lastNote = person.interactions.max(by: { $0.date < $1.date })?.note
        let commitment = person.commitments
            .filter { !$0.isDone }
            .min(by: { $0.createdAt < $1.createdAt })?
            .text
        return NudgeCopy.cardContext(lastInteractionNote: lastNote, firstOpenCommitment: commitment)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: EmberTheme.spacingM) {
            NavigationLink {
                PersonDetailView(person: person)
            } label: {
                HStack(alignment: .top, spacing: EmberTheme.spacingM) {
                    PersonAvatarView(person: person, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.displayNameCache)
                            .font(.headline)
                        Text(log.reason)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let context {
                            Text(context)
                                .font(.subheadline)
                                .lineLimit(2)
                                .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack {
                Button {
                    services.router.composePersonID = log.personID
                } label: {
                    Label(String(localized: "Message"), systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)

                Button(String(localized: "We spoke")) {
                    actionCount += 1
                    Task { await services.nudgeEngine.handleWeSpoke(personID: log.personID, nudgeLogID: log.id) }
                }
                .buttonStyle(.bordered)
                .accessibilityHint(String(localized: "Logs that you were in touch and clears this suggestion."))

                Button(String(localized: "Snooze")) {
                    actionCount += 1
                    Task { await services.nudgeEngine.handleSnooze(personID: log.personID, nudgeLogID: log.id) }
                }
                .buttonStyle(.bordered)
                .accessibilityHint(String(localized: "Hides this suggestion for two weeks."))
            }
            .controlSize(.small)
        }
        .emberCard()
        .sensoryFeedback(.success, trigger: actionCount)
    }
}
