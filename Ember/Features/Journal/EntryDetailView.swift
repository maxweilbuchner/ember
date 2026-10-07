// EntryDetailView.swift

import SwiftData
import SwiftUI

struct EntryDetailView: View {
    let entry: Entry
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showReview = false
    @State private var showEditor = false
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(entry.date.formatted(date: .complete, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.text)
                    .textSelection(.enabled)
                if !entry.mentions.isEmpty {
                    // Flows so chips keep their natural width and wrap.
                    FlowLayout {
                        ForEach(entry.mentions) { person in
                            let chip = EmberChip(
                                text: NameMatcher.compactName(person.displayNameCache),
                                systemImage: person.isPartnerMode ? "heart.fill" : nil
                            )
                            if person.isPlaceholder {
                                chip
                            } else {
                                NavigationLink {
                                    PersonDetailView(person: person)
                                } label: {
                                    chip
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(String(localized: "Open \(person.displayNameCache)"))
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .emberCanvas()
        .navigationTitle(String(localized: "Entry"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem {
                Menu {
                    Button {
                        showEditor = true
                    } label: {
                        Label(String(localized: "Edit text"), systemImage: "pencil")
                    }
                    Button {
                        showReview = true
                    } label: {
                        Label(String(localized: "Review mentions"), systemImage: "person.crop.circle.badge.checkmark")
                    }
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label(String(localized: "Delete entry"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(String(localized: "More options"))
            }
        }
        .sheet(isPresented: $showReview) {
            MentionReviewSheet(entry: entry)
        }
        .sheet(isPresented: $showEditor) {
            EntryTextEditorSheet(entry: entry)
        }
        .alert(String(localized: "Delete this entry?"), isPresented: $confirmDelete) {
            Button(String(localized: "Delete"), role: .destructive) {
                modelContext.delete(entry)
                try? modelContext.save()
                dismiss()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "This can't be undone."))
        }
    }
}

/// Fixes a typo or adds a line. Tags stay exactly as they are — editing prose
/// never silently changes who an entry is about; "Review mentions" does that.
private struct EntryTextEditorSheet: View {
    let entry: Entry
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var text: String

    init(entry: Entry) {
        self.entry = entry
        _text = State(initialValue: entry.text)
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($isFocused)
                .padding(EmberTheme.spacingM)
                .scrollContentBackground(.hidden)
                .emberCardSurface()
                .padding()
                .emberCanvas()
                .navigationTitle(String(localized: "Edit entry"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel")) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Save")) {
                            entry.text = trimmedText
                            try? modelContext.save()
                            dismiss()
                        }
                        .disabled(trimmedText.isEmpty || trimmedText == entry.text)
                    }
                }
                .onAppear { isFocused = true }
        }
        .presentationDetents([.medium, .large])
    }
}
