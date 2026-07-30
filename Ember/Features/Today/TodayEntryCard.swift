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
        VStack(alignment: .leading, spacing: EmberTheme.spacingM) {
            NavigationLink {
                EntryDetailView(entry: entry)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: EmberTheme.spacingS) {
                    Text(entry.previewLine)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(entry.date, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExtracting {
                HStack(spacing: EmberTheme.spacingXS) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(String(localized: "Looking for people…"))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ExtractionChipsView(entry: entry, suggestions: services.entrySuggestions[entry.id])
        }
        .emberCard()
        .animation(EmberTheme.calm, value: isExtracting)
    }
}
