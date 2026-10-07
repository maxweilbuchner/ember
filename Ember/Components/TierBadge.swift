// TierBadge.swift

import SwiftUI

/// A person's keep-in-touch choice as a chip ("Close", "♥ Partner").
struct TierBadge: View {
    let choice: KeepInTouch

    var body: some View {
        EmberChip(text: choice.title, systemImage: choice.systemImage)
    }
}
