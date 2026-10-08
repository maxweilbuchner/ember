// EmptyStateView.swift

import SwiftUI

/// Calm, encouraging, instructive — the spirit of v1's QuietSurfer.
/// Never a zero-count, never a deficit.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    /// Optional single way forward ("Add people") — an empty state should
    /// say what to do and, where it can, let you do it.
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: EmberTheme.emptyStateIconSize))
                .foregroundStyle(Color.accentColor.opacity(0.7))
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, EmberTheme.spacingS)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
