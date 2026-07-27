// TodayView.swift

import SwiftData
import SwiftUI

/// The default tab — and effectively the app: capture at the top, then pending
/// review chips, today's nudges, and upcoming birthdays.
struct TodayView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @Query(sort: \NudgeLog.date, order: .reverse) private var nudgeLogs: [NudgeLog]
    @Query private var people: [Person]
    @State private var birthdays: [BirthdayItem] = []

    private var pendingEntries: [Entry] {
        entries.filter { $0.extractionState == .pending }
    }

    private var activeNudges: [(log: NudgeLog, person: Person)] {
        let peopleByID = Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return nudgeLogs
            .filter { $0.outcome == .pending && Date.now.timeIntervalSince($0.date) < 7 * 86_400 }
            .compactMap { log in peopleByID[log.personID].map { (log, $0) } }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    CaptureComposer()

                    if !activeNudges.isEmpty {
                        sectionHeader(String(localized: "Worth a message"))
                        ForEach(activeNudges, id: \.log.id) { pair in
                            NudgeCardView(log: pair.log, person: pair.person)
                        }
                    }

                    if !pendingEntries.isEmpty && !people.isEmpty {
                        sectionHeader(String(localized: "Anyone mentioned?"))
                        ForEach(pendingEntries.prefix(3)) { entry in
                            PendingEntryCard(entry: entry)
                        }
                    }

                    if !birthdays.isEmpty {
                        sectionHeader(String(localized: "Birthdays coming up"))
                        BirthdayList(items: birthdays)
                    }
                }
                .padding()
            }
            .navigationTitle(String(localized: "Today"))
            .task {
                birthdays = await services.birthdayEngine.upcoming(withinDays: 7)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
    }
}

private struct BirthdayList: View {
    let items: [BirthdayItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items) { item in
                HStack(spacing: 10) {
                    Image(systemName: "gift")
                        .foregroundStyle(Color.accentColor)
                    Text(item.displayName)
                        .fontWeight(.medium)
                    Spacer()
                    Text(birthdayPhrase(item.daysAway))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func birthdayPhrase(_ daysAway: Int) -> String {
        switch daysAway {
        case 0: String(localized: "today 🎂")
        case 1: String(localized: "tomorrow")
        default: String(localized: "in \(daysAway) days")
        }
    }
}
