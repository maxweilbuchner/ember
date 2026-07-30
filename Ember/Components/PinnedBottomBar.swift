// PinnedBottomBar.swift

import SwiftUI

/// Material-backed bottom action bar. Apply via
/// `.safeAreaInset(edge: .bottom) { PinnedBottomBar { … } }` so list content
/// scrolls under it instead of colliding with a floating button.
struct PinnedBottomBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: EmberTheme.spacingM) {
            content
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.vertical, EmberTheme.spacingM)
        .background(.bar)
    }
}
