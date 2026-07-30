// EntryDetailView.swift

import SwiftData
import SwiftUI

struct EntryDetailView: View {
    let entry: Entry
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showReview = false
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
                            EmberChip(
                                text: NameMatcher.compactName(person.displayNameCache),
                                systemImage: person.isPartnerMode ? "heart.fill" : nil
                            )
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
