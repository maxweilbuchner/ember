// HeroHeader.swift

import SwiftUI

/// The one hero presentation (onboarding screens, lock screen): 56pt accent
/// symbol, ink display title, optional secondary message. `.brand` keeps the
/// large wordmark treatment for the onboarding welcome only.
struct HeroHeader: View {
    enum Style {
        case standard
        case brand
    }

    let systemImage: String
    let title: String
    var message: String?
    var style: Style = .standard

    var body: some View {
        VStack(spacing: EmberTheme.spacingL) {
            Image(systemName: systemImage)
                .font(.system(size: EmberTheme.heroIconSize))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(style == .brand ? .largeTitle.weight(.bold) : .title2.weight(.semibold))
                .foregroundStyle(Color(.emberInk))
            if let message {
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, EmberTheme.spacingXL)
            }
        }
    }
}
