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
                if services.security.isLocked {
                    LockedView()
                } else if scenePhase != .active {
                    shield
                }
            }
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
                .font(.system(size: 48))
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
