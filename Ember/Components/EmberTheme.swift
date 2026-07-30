// EmberTheme.swift

import SwiftUI

/// The single owner of Ember's visual constants (spec §5.4: warm amber/terracotta
/// on warm off-white/charcoal, "a well-kept notebook, not a dashboard", calm motion).
/// Native-first: system semantics (destructive red, .secondary labels, materials)
/// stay untouched — this file only covers what the system can't decide for us.
///
/// Color roles (asset catalog): AccentColor = interactive amber; EmberTerracotta =
/// warm secondary (avatar gradient end); EmberCream = app canvas; EmberCard = card
/// surface; EmberInk = hero/display titles only, never body text.
/// The lock-screen widget intentionally uses `flame.fill` (filled symbols carry the
/// correct weight at accessory sizes) while in-app heroes use the outline `flame`.
enum EmberTheme {
    // Spacing scale — for new and edited layout code.
    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 12
    static let spacingL: CGFloat = 16
    static let spacingXL: CGFloat = 24
    static let spacingXXL: CGFloat = 28

    static let cardCornerRadius: CGFloat = 16
    /// Hero flame and permission-screen icons (onboarding, lock, shield).
    static let heroIconSize: CGFloat = 56
    /// Icon size for content-level empty states (EmptyStateView).
    static let emptyStateIconSize: CGFloat = 40

    /// The only animation curve in the app. Every `withAnimation`/`.animation`
    /// call uses this; nothing loops, nothing bounces.
    static let calm = Animation.smooth(duration: 0.3)

    /// Insertion/removal transition for cards and chips. Any scale/move motion
    /// must degrade to a plain crossfade under Reduce Motion; pure opacity fades
    /// and `.symbolEffect`/`.contentTransition` are exempt (system-handled).
    static func calmTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.98, anchor: .center))
    }
}

extension View {
    /// The warm paper canvas behind every screen-level List/ScrollView.
    func emberCanvas() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color(.emberCream).ignoresSafeArea())
    }

    /// Padded card on the canvas (nudges, birthdays, pending entries).
    func emberCard() -> some View {
        self
            .padding()
            .background(RoundedRectangle(cornerRadius: EmberTheme.cardCornerRadius).fill(Color(.emberCard)))
    }

    /// Card surface without the standard padding, for fields that manage their own
    /// insets (capture field, Compose's draft editor).
    func emberCardSurface() -> some View {
        background(RoundedRectangle(cornerRadius: EmberTheme.cardCornerRadius).fill(Color(.emberCard)))
    }
}
