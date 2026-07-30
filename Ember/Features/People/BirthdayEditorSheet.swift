// BirthdayEditorSheet.swift

import SwiftData
import SwiftUI

/// Manual-birthday editor — the fill-in for people whose linked contact has no
/// birthday, or who aren't linked at all. Contact-provided birthdays are
/// read-only in Ember by design; those are edited in Contacts.
struct BirthdayEditorSheet: View {
    @Bindable var person: Person
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var month: Int
    @State private var day: Int
    @State private var includeYear: Bool
    @State private var year: Int
    /// Remembered, not asked every time — but always visible while saving, so
    /// writing to someone's address book is never a surprise.
    @AppStorage("writeBirthdaysToContacts") private var alsoSaveToContacts = false

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
                if person.contactID != nil {
                    Section {
                        Toggle(String(localized: "Also save to Contacts"), isOn: $alsoSaveToContacts)
                    } footer: {
                        Text(String(localized: "Adds the birthday to \(person.displayNameCache)'s contact card on this device. Their card then keeps it — you'd edit it in Contacts from then on."))
                    }
                }
                if person.manualBirthday != nil {
                    Section {
                        Button(String(localized: "Remove birthday"), role: .destructive) {
                            Task {
                                await BirthdayWriteBack.save(
                                    nil,
                                    for: person,
                                    alsoToContacts: alsoSaveToContacts,
                                    writer: services.contacts,
                                    context: modelContext
                                )
                                dismiss()
                            }
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
                        let birthday = DateComponents(
                            year: includeYear ? year : nil,
                            month: month,
                            day: day
                        )
                        Task {
                            await BirthdayWriteBack.save(
                                birthday,
                                for: person,
                                alsoToContacts: alsoSaveToContacts,
                                writer: services.contacts,
                                context: modelContext
                            )
                            dismiss()
                        }
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
