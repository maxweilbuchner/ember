// TierBadge.swift

import SwiftUI

struct TierBadge: View {
    let tier: CadenceTier

    var body: some View {
        EmberChip(text: tier.title)
    }
}
