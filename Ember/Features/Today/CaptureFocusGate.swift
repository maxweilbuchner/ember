// CaptureFocusGate.swift

import Foundation

/// Decides when the capture field may raise the keyboard.
///
/// Focusing during the first layout pass builds the keyboard into a window that
/// isn't on screen yet, and — because the app lock, the onboarding cover and a
/// nudge's Compose sheet are all drawn *over* a still-live Today tab — it also
/// put the keyboard behind them (GH #12).
///
/// Spec §1.3 ("cold start to typing < 1 second") means focus may only ever be
/// deferred, never dropped: the field comes up the instant the app is genuinely
/// on screen, and an explicit request survives the lock rather than being
/// swallowed.
nonisolated enum CaptureFocusGate {
    struct Input: Equatable, Sendable {
        /// `scenePhase == .active` — the window is key and visible.
        var isSceneActive = false
        /// `LockedView` is an overlay, so the composer is alive underneath it.
        var isLocked = false
        /// A Compose sheet is up, e.g. a cold launch from a nudge tap.
        var isCoveredByModal = false
        var hasCompletedOnboarding = false
        /// This launch's one automatic focus has been used or spent.
        var autoFocusUsed = false
        /// A deep link asked for the field (`ember://capture`, lock-screen widget).
        var isCaptureRequested = false
        /// Screenshot runs want the Today content, not the keyboard.
        var isDemoSeed = false
    }

    enum Decision: Equatable, Sendable {
        /// Raise the keyboard now, consuming any pending request.
        case focus
        /// Not yet — hold, do not drop, a pending request.
        case wait
        /// Spend the one-shot automatic focus without using it, so it can never
        /// fire late and surprise the user.
        case cancelAutoFocus
        case idle
    }

    static func decide(_ input: Input) -> Decision {
        // An explicit request is user intent: it survives the lock, and it
        // outlives the one-shot automatic focus.
        if input.isCaptureRequested {
            return isReady(input) ? .focus : .wait
        }
        guard !input.autoFocusUsed, !input.isDemoSeed else { return .idle }
        // A nudge tap redirected the user's intent; firing a held focus when
        // they dismiss the sheet would pop a keyboard out of nowhere.
        guard !input.isCoveredByModal else { return .cancelAutoFocus }
        return isReady(input) ? .focus : .wait
    }

    private static func isReady(_ input: Input) -> Bool {
        input.isSceneActive
            && !input.isLocked
            && !input.isCoveredByModal
            && input.hasCompletedOnboarding
    }
}
