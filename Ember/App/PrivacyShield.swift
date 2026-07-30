// PrivacyShield.swift

import SwiftUI

/// Covers content in the app switcher (blur + mark whenever the scene isn't
/// active) and engages the app lock on backgrounding.
struct PrivacyShield: ViewModifier {
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .overlay {
                // Pure crossfades — fine under Reduce Motion.
                if services.security.isLocked {
                    LockedView()
                        .transition(.opacity)
                } else if scenePhase != .active {
                    shield
                        .transition(.opacity)
                }
            }
            .animation(EmberTheme.calm, value: services.security.isLocked)
            .animation(EmberTheme.calm, value: scenePhase)
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    services.security.lockIfEnabled()
                }
            }
    }

    private var shield: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            Image(systemName: "flame")
                .font(.system(size: EmberTheme.heroIconSize))
                .foregroundStyle(Color.accentColor)
        }
        .ignoresSafeArea()
    }
}

extension View {
    func privacyShield() -> some View {
        modifier(PrivacyShield())
    }
}
