// JournalListView.swift

import SwiftData
import SwiftUI

struct JournalListView: View {
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @State private var searchText = ""
    @State private var selectedDay: Date?
    @State private var showDayPicker = false

    private var filteredEntries: [Entry] {
        var result = entries
        if let selectedDay {
            let calendar = Calendar.current
            result = result.filter { calendar.isDate($0.date, inSameDayAs: selectedDay) }
        }
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            result = result.filter { $0.text.localizedStandardContains(trimmed) }
        }
        return result
    }

    /// Entries grouped by calendar day, newest day first — a notebook reads
    /// by day, and the date then needn't repeat on every row.
    private var entriesByDay: [(day: Date, entries: [Entry])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filteredEntries) { calendar.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { day in
            (day: day, entries: (groups[day] ?? []).sorted { $0.date > $1.date })
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return String(localized: "Today") }
        if calendar.isDateInYesterday(day) { return String(localized: "Yesterday") }
        if calendar.isDate(day, equalTo: .now, toGranularity: .year) {
            return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    EmptyStateView(
                        systemImage: "book.closed",
                        title: String(localized: "Your journal starts here"),
                        message: String(localized: "Anything you jot down on Today lands in this quiet archive.")
                    )
                } else {
                    List {
                        if let selectedDay {
                            HStack {
                                Text(selectedDay, style: .date)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(String(localized: "Show all")) { self.selectedDay = nil }
                                    .font(.subheadline)
                            }
                        }
                        ForEach(entriesByDay, id: \.day) { group in
                            Section(dayTitle(group.day)) {
                                ForEach(group.entries) { entry in
                                    NavigationLink {
                                        EntryDetailView(entry: entry)
                                    } label: {
                                        JournalRow(entry: entry)
                                    }
                                }
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: String(localized: "Search entries"))
                    .overlay {
                        if filteredEntries.isEmpty {
                            if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                                ContentUnavailableView.search(text: searchText)
                            } else if selectedDay != nil {
                                EmptyStateView(
                                    systemImage: "calendar",
                                    title: String(localized: "A quiet day"),
                                    message: String(localized: "Nothing was captured here. Try another day, or show all entries.")
                                )
                            }
                        }
                    }
                }
            }
            .emberCanvas()
            .navigationTitle(String(localized: "Journal"))
            .toolbar {
                if !entries.isEmpty {
                    ToolbarItem {
                        Button {
                            showDayPicker = true
                        } label: {
                            Image(systemName: "calendar")
                        }
                        .accessibilityLabel(String(localized: "Jump to day"))
                    }
                }
            }
            .sheet(isPresented: $showDayPicker) {
                DayPickerSheet(selectedDay: $selectedDay)
                    .presentationDetents([.medium])
            }
        }
    }
}

private struct JournalRow: View {
    let entry: Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.previewLine)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(entry.date, style: .time)
                let names = entry.mentions.map { NameMatcher.compactName($0.displayNameCache) }
                if !names.isEmpty {
                    Text(verbatim: "·")
                    Text(names.joined(separator: ", "))
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct DayPickerSheet: View {
    @Binding var selectedDay: Date?
    @Environment(\.dismiss) private var dismiss
    @State private var day = Date.now

    var body: some View {
        NavigationStack {
            VStack(spacing: EmberTheme.spacingM) {
                DatePicker(String(localized: "Jump to day"), selection: $day, in: ...Date.now, displayedComponents: [.date])
                    .datePickerStyle(.graphical)
                if selectedDay != nil {
                    Button(String(localized: "Show all days")) {
                        selectedDay = nil
                        dismiss()
                    }
                }
            }
            .padding()
            .frame(maxHeight: .infinity, alignment: .top)
            .emberCanvas()
            .navigationTitle(String(localized: "Jump to day"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Show")) {
                        selectedDay = day
                        dismiss()
                    }
                }
            }
        }
    }
}
