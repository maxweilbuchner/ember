// TodayView.swift

import SwiftData
import SwiftUI

/// The default tab — and effectively the app: capture at the top, then today's
/// nudges, today's entries with their tags, and upcoming dates. When all of
/// that is quiet, a short note says what the field is for (spec §5.3).
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

                    if isQuiet {
                        quietNote
                            .transition(.opacity)
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
                await refreshOccasions()
            }
            // Dates change while the app sits in the background (midnight, a
            // birthday added in Contacts) — re-read when it comes back.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await refreshOccasions() }
                }
            }
        }
    }

    private func refreshOccasions() async {
        occasions = await services.dateEngine.upcoming(withinDays: 7)
    }

    private var isQuiet: Bool {
        activeNudges.isEmpty && todaysEntries.isEmpty && occasions.isEmpty
    }

    private var hasPeople: Bool {
        people.contains { !$0.isPlaceholder }
    }

    private var quietNote: some View {
        VStack(alignment: .leading, spacing: EmberTheme.spacingS) {
            Label(String(localized: "A quiet day"), systemImage: "leaf")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text(hasPeople
                ? String(localized: "Jot down who you saw, called, or texted — a line is enough. Ember tags the people for you, and once a week suggests a few who'd enjoy hearing from you.")
                : String(localized: "Add the people you'd like to keep close on the People tab. Then jot down who you saw or talked to — a line is enough."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, EmberTheme.spacingXS)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
    }
}

/// Upcoming birthdays and dates. A row is one tap into Compose — an occasion
/// is a reason to reach out, so it leads straight to the message (§1.3).
private struct OccasionList: View {
    let items: [UpcomingOccasion]
    @Environment(AppServices.self) private var services

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items) { item in
                Button {
                    services.router.composePersonID = item.personID
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: symbolName(for: item.kind))
                            .foregroundStyle(Color.accentColor)
                        Text(title(for: item))
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Text(phrase(for: item))
                            .foregroundStyle(.secondary)
                        Image(systemName: "paperplane")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(String(localized: "Opens a message to \(item.displayName)."))
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
