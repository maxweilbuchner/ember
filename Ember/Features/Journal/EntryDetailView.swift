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
                    HStack(spacing: 8) {
                        ForEach(entry.mentions) { person in
                            Text(person.displayNameCache)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
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
            }
        }
        .sheet(isPresented: $showReview) {
            MentionReviewSheet(entry: entry)
        }
        .confirmationDialog(String(localized: "Delete this entry?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(String(localized: "Delete"), role: .destructive) {
                modelContext.delete(entry)
                try? modelContext.save()
                dismiss()
            }
        }
    }
}
