// EmberChip.swift

import SwiftUI

/// The one capsule chip (tier badges, mention chips). Static display only —
/// tappable chips stay native bordered buttons (see ExtractionChipsView).
struct EmberChip: View {
    let text: String
    var systemImage: String?
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: EmberTheme.spacingXS) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.15)))
        .foregroundStyle(tint)
    }
}
