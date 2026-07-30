// TodayEntryCard.swift

import SwiftData
import SwiftUI

/// One of today's entries, with its tags. Nothing here demands an action: the
/// entry is already saved, confident people are already tagged, and anything
/// left is a one-tap chip the user can ignore.
struct TodayEntryCard: View {
    let entry: Entry
    @Environment(AppServices.self) private var services

    private var isExtracting: Bool {
        services.extractingEntryIDs.contains(entry.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: EmberTheme.spacingS) {
            NavigationLink {
                EntryDetailView(entry: entry)
            } label: {
                Text(entry.previewLine)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ExtractionChipsView(entry: entry, suggestions: services.entrySuggestions[entry.id])

            HStack(spacing: EmberTheme.spacingXS) {
                if isExtracting {
                    ProgressView()
                        .controlSize(.mini)
                    Text(String(localized: "Looking for people…"))
                } else {
                    Text(entry.date, style: .time)
                }
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .emberCard()
        .animation(EmberTheme.calm, value: isExtracting)
    }
}
