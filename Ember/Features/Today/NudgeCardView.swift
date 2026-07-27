// NudgeCardView.swift

import SwiftData
import SwiftUI

/// A nudge on the Today tab: context-forward, with the same actions as the
/// notification, plus the honest "why" straight from the NudgeLog.
struct NudgeCardView: View {
    let log: NudgeLog
    let person: Person
    @Environment(AppServices.self) private var services
    @State private var showPerson = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                PersonAvatarView(person: person, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.displayNameCache)
                        .font(.headline)
                    Text(log.reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack {
                Button {
                    showPerson = true
                } label: {
                    Label(String(localized: "Open"), systemImage: "person.crop.circle")
                }
                .buttonStyle(.borderedProminent)

                Button(String(localized: "We spoke")) {
                    Task { await services.nudgeEngine.handleWeSpoke(personID: log.personID, nudgeLogID: log.id) }
                }
                .buttonStyle(.bordered)

                Button(String(localized: "Snooze")) {
                    Task { await services.nudgeEngine.handleSnooze(personID: log.personID, nudgeLogID: log.id) }
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
        .sheet(isPresented: $showPerson) {
            NavigationStack {
                PersonDetailView(person: person)
            }
        }
    }
}
