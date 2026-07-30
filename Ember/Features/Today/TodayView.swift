// TodayView.swift

import SwiftData
import SwiftUI

/// The default tab — and effectively the app: capture at the top, then pending
/// review chips, today's nudges, and upcoming birthdays.
struct TodayView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @Query(sort: \NudgeLog.date, order: .reverse) private var nudgeLogs: [NudgeLog]
    @Query private var people: [Person]
    @State private var occasions: [UpcomingOccasion] = []
    @AppStorage("showTodaysEntries") private var showTodaysEntries = true

    private var todaysEntries: [Entry] {
        entries.filter { Calendar.current.isDateInToday($0.date) }
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
                                .transition(EmberTheme.calmTransition(reduceMotion: reduceMotion))
                        }
                    }

                    if !todaysEntries.isEmpty {
                        HStack {
                            sectionHeader(String(localized: "Today's entries"))
                            Spacer()
                            Button(showTodaysEntries
                                ? String(localized: "Hide")
                                : String(localized: "Show")) {
                                showTodaysEntries.toggle()
                            }
                            .font(.subheadline)
                        }
                        if showTodaysEntries {
                            ForEach(todaysEntries) { entry in
                                TodayEntryCard(entry: entry)
                                    .transition(EmberTheme.calmTransition(reduceMotion: reduceMotion))
                            }
                        }
                    }

                    if !occasions.isEmpty {
                        sectionHeader(String(localized: "Coming up"))
                        OccasionList(items: occasions)
                    }
                }
                .padding()
                // Card removals originate in async engine calls, so animation is
                // keyed on the derived ID lists rather than withAnimation scopes.
                .animation(EmberTheme.calm, value: activeNudges.map(\.log.id))
                .animation(EmberTheme.calm, value: todaysEntries.map(\.id))
                .animation(EmberTheme.calm, value: showTodaysEntries)
            }
            .scrollDismissesKeyboard(.interactively)
            .emberCanvas()
            .navigationTitle(String(localized: "Today"))
            .task {
                occasions = await services.dateEngine.upcoming(withinDays: 7)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
    }
}

private struct OccasionList: View {
    let items: [UpcomingOccasion]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items) { item in
                HStack(spacing: 10) {
                    Image(systemName: symbolName(for: item.kind))
                        .foregroundStyle(Color.accentColor)
                    Text(title(for: item))
                        .fontWeight(.medium)
                    Spacer()
                    Text(phrase(for: item))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .emberCard()
    }

    private func symbolName(for kind: UpcomingOccasion.Kind) -> String {
        switch kind {
        case .birthday: "gift"
        case .custom: "calendar.badge.clock"
        }
    }

    private func title(for item: UpcomingOccasion) -> String {
        switch item.kind {
        case .birthday: item.displayName
        case .custom(let label): String(localized: "\(item.displayName) — \(label)")
        }
    }

    private func phrase(for item: UpcomingOccasion) -> String {
        if item.daysAway == 0, case .birthday = item.kind {
            return String(localized: "today 🎂")
        }
        return NeutralPhrases.upcoming(daysAway: item.daysAway)
    }
}
