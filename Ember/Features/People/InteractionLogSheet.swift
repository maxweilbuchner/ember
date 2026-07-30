// InteractionLogSheet.swift

import SwiftData
import SwiftUI

/// 2-tap interaction logging from the Person screen: channel + save.
/// Note and (approximate) past dates are optional refinements.
struct InteractionLogSheet: View {
    let person: Person
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var channel: Channel = .inPerson
    @State private var note = ""
    @State private var date = Date.now
    @State private var isApproximate = false
    @State private var saveCount = 0

    var body: some View {
        NavigationStack {
            Form {
                Picker(String(localized: "How"), selection: $channel) {
                    ForEach(Channel.allCases, id: \.self) { channel in
                        Label(channel.title, systemImage: channel.symbolName).tag(channel)
                    }
                }
                .pickerStyle(.inline)

                Section {
                    TextField(String(localized: "Note — what did you talk about? (optional)"), text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section {
                    DatePicker(
                        String(localized: "When"),
                        selection: $date,
                        in: ...Date.now,
                        displayedComponents: isApproximate ? [.date] : [.date, .hourAndMinute]
                    )
                    Toggle(String(localized: "Rough date (\"sometime last week\")"), isOn: $isApproximate)
                }
            }
            .emberCanvas()
            .navigationTitle(String(localized: "With \(person.displayNameCache)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) { save() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sensoryFeedback(.success, trigger: saveCount)
    }

    private func save() {
        saveCount += 1
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        modelContext.insert(Interaction(
            person: person,
            date: date,
            dateIsApproximate: isApproximate,
            channel: channel,
            note: trimmedNote.isEmpty ? nil : trimmedNote
        ))
        try? modelContext.save()
        dismiss()
    }
}
