// TierBadge.swift

import SwiftUI

struct TierBadge: View {
    let tier: CadenceTier

    var body: some View {
        Text(tier.title)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            .foregroundStyle(Color.accentColor)
    }
}
