// LockedView.swift

import SwiftUI

/// Calm full-screen lock: auto-attempts FaceID on appear, offers a retry
/// button after a failure. Port of the v1 LockedView behaviour.
struct LockedView: View {
    @Environment(AppServices.self) private var services
    @State private var attemptFailed = false

    var body: some View {
        ZStack {
            Color(.emberCream)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "flame")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.accentColor)
                Text(String(localized: "Ember is locked"))
                    .font(.title3.weight(.semibold))
                if attemptFailed {
                    Button(String(localized: "Unlock")) {
                        Task { await tryUnlock() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
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
