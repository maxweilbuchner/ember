// LockedView.swift

import SwiftUI

/// Calm full-screen lock: auto-attempts FaceID on appear, offers a retry
/// button after a failure. Port of the v1 LockedView behaviour.
struct LockedView: View {
    @Environment(AppServices.self) private var services
    @State private var attemptFailed = false

    var body: some View {
        VStack(spacing: EmberTheme.spacingL) {
            HeroHeader(systemImage: "flame", title: String(localized: "Ember is locked"))
            if attemptFailed {
                Button(String(localized: "Unlock")) {
                    Task { await tryUnlock() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.emberCream).ignoresSafeArea())
        .task {
            await tryUnlock()
        }
    }

    private func tryUnlock() async {
        attemptFailed = false
        let unlocked = await services.security.attemptUnlock()
        if !unlocked {
            attemptFailed = true
        }
    }
}
