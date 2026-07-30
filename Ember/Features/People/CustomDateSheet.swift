// CustomDateSheet.swift

import SwiftData
import SwiftUI

/// Adds a custom important date to a person — anniversary, first met, name day.
/// Free-text label with suggestion chips, plus the shared month/day/year wheels.
struct CustomDateSheet: View {
    let person: Person
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var month = 1
    @State private var day = 1
    @State private var includeYear = false
    @State private var year = Calendar.current.component(.year, from: .now)

    private var suggestions: [String] {
        [
            String(localized: "Anniversary"),
            String(localized: "First met"),
            String(localized: "Name day"),
        ]
    }

    private var trimmedLabel: String {
        label.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Anniversary, first met…"), text: $label)
                    HStack(spacing: EmberTheme.spacingS) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(suggestion) { label = suggestion }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .font(.caption)
                        }
                    }
                }
                Section {
                    MonthDayYearPicker(month: $month, day: $day, includeYear: $includeYear, year: $year)
                }
            }
            .navigationTitle(String(localized: "Add a date"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        modelContext.insert(CustomDate(
                            person: person,
                            label: trimmedLabel,
                            month: month,
                            day: day,
                            year: includeYear ? year : nil
                        ))
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(trimmedLabel.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
