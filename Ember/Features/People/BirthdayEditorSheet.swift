// BirthdayEditorSheet.swift

import SwiftData
import SwiftUI

/// Manual-birthday editor — the fill-in for people whose linked contact has no
/// birthday, or who aren't linked at all. Contact-provided birthdays are
/// read-only in Ember by design; those are edited in Contacts.
struct BirthdayEditorSheet: View {
    @Bindable var person: Person
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var month: Int
    @State private var day: Int
    @State private var includeYear: Bool
    @State private var year: Int

    init(person: Person) {
        self.person = person
        let existing = person.manualBirthday
        let currentYear = Calendar.current.component(.year, from: .now)
        _month = State(initialValue: existing?.month ?? 1)
        _day = State(initialValue: existing?.day ?? 1)
        _includeYear = State(initialValue: existing?.year != nil)
        _year = State(initialValue: existing?.year ?? currentYear - 30)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MonthDayYearPicker(month: $month, day: $day, includeYear: $includeYear, year: $year)
                }
                if person.manualBirthday != nil {
                    Section {
                        Button(String(localized: "Remove birthday"), role: .destructive) {
                            person.manualBirthday = nil
                            try? modelContext.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Birthday"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        person.manualBirthday = DateComponents(
                            year: includeYear ? year : nil,
                            month: month,
                            day: day
                        )
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Month/day/optional-year pickers whose day range follows the chosen month —
/// February without a year allows 29, so Feb-29 birthdays stay enterable.
/// Shared with the custom-date sheet.
struct MonthDayYearPicker: View {
    @Binding var month: Int
    @Binding var day: Int
    @Binding var includeYear: Bool
    @Binding var year: Int

    private var calendar: Calendar { Calendar.current }
    private var dayRange: ClosedRange<Int> {
        BirthdayMath.validDayRange(month: month, year: includeYear ? year : nil, calendar: calendar)
    }
    private var yearRange: ClosedRange<Int> {
        let currentYear = calendar.component(.year, from: .now)
        return (currentYear - 120)...currentYear
    }

    var body: some View {
        Picker(String(localized: "Month"), selection: $month) {
            ForEach(1...12, id: \.self) { month in
                Text(calendar.monthSymbols[month - 1]).tag(month)
            }
        }
        Picker(String(localized: "Day"), selection: $day) {
            ForEach(dayRange, id: \.self) { day in
                Text(verbatim: "\(day)").tag(day)
            }
        }
        Toggle(String(localized: "Include year"), isOn: $includeYear)
            .onChange(of: month) { clampDay() }
            .onChange(of: includeYear) { clampDay() }
            .onChange(of: year) { clampDay() }
        if includeYear {
            Picker(String(localized: "Year"), selection: $year) {
                ForEach(yearRange.reversed(), id: \.self) { year in
                    Text(verbatim: "\(year)").tag(year)
                }
            }
        }
    }

    /// Keeps the day valid when the month or year selection shrinks the range.
    private func clampDay() {
        if day > dayRange.upperBound {
            day = dayRange.upperBound
        }
    }
}
