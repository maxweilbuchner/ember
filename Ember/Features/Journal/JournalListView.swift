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
                        ForEach(filteredEntries) { entry in
                            NavigationLink {
                                EntryDetailView(entry: entry)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.previewLine)
                                        .lineLimit(2)
                                    HStack(spacing: 6) {
                                        Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                        if !entry.mentions.isEmpty {
                                            Text("·")
                                            Text(entry.mentions.map(\.displayNameCache).joined(separator: ", "))
                                                .lineLimit(1)
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: String(localized: "Search entries"))
                }
            }
            .navigationTitle(String(localized: "Journal"))
            .toolbar {
                if !entries.isEmpty {
                    ToolbarItem {
                        Button {
                            showDayPicker = true
                        } label: {
                            Image(systemName: "calendar")
                        }
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

private struct DayPickerSheet: View {
    @Binding var selectedDay: Date?
    @Environment(\.dismiss) private var dismiss
    @State private var day = Date.now

    var body: some View {
        NavigationStack {
            DatePicker(String(localized: "Jump to day"), selection: $day, in: ...Date.now, displayedComponents: [.date])
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle(String(localized: "Jump to day"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
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
