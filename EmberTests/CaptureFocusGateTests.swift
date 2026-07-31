// CaptureFocusGateTests.swift

import Foundation
import Testing
@testable import Ember

@Suite("Capture focus gate")
struct CaptureFocusGateTests {
    /// A launch that is fully on screen, unlocked, onboarded, and hasn't focused yet.
    private func ready(
        active: Bool = true,
        locked: Bool = false,
        covered: Bool = false,
        onboarded: Bool = true,
        used: Bool = false,
        requested: Bool = false,
        demo: Bool = false
    ) -> CaptureFocusGate.Input {
        CaptureFocusGate.Input(
            isSceneActive: active,
            isLocked: locked,
            isCoveredByModal: covered,
            hasCompletedOnboarding: onboarded,
            autoFocusUsed: used,
            isCaptureRequested: requested,
            isDemoSeed: demo
        )
    }

    @Test func coldStartWaitsForTheSceneThenFocuses() {
        // .onAppear runs while the scene is still inactive — that's the bug.
        #expect(CaptureFocusGate.decide(ready(active: false)) == .wait)
        #expect(CaptureFocusGate.decide(ready()) == .focus)
    }

    @Test func lockedLaunchWaitsInsteadOfFocusingBehindTheLockScreen() {
        #expect(CaptureFocusGate.decide(ready(locked: true)) == .wait)
        #expect(CaptureFocusGate.decide(ready()) == .focus)
    }

    @Test func onboardingWaitsThenFocusesOnceTheCoverIsGone() {
        #expect(CaptureFocusGate.decide(ready(onboarded: false)) == .wait)
        #expect(CaptureFocusGate.decide(ready(requested: true)) == .focus)
    }

    @Test func widgetRequestSurvivesTheLockAndFiresOnUnlock() {
        #expect(CaptureFocusGate.decide(ready(locked: true, requested: true)) == .wait)
        #expect(CaptureFocusGate.decide(ready(requested: true)) == .focus)
    }

    @Test func widgetRequestOutlivesTheOneShotAutoFocus() {
        #expect(CaptureFocusGate.decide(ready(used: true)) == .idle)
        #expect(CaptureFocusGate.decide(ready(used: true, requested: true)) == .focus)
    }

    @Test func aComposeSheetSpendsTheAutoFocusRatherThanQueueingIt() {
        // Cold launch from a nudge tap: no keyboard behind the sheet, and none
        // popping up out of nowhere when it's dismissed.
        #expect(CaptureFocusGate.decide(ready(covered: true)) == .cancelAutoFocus)
        #expect(CaptureFocusGate.decide(ready(covered: true, requested: true)) == .wait)
    }

    @Test func returningToTheTabDoesNotStealFocusBack() {
        #expect(CaptureFocusGate.decide(ready(used: true)) == .idle)
    }

    @Test func demoSeedNeverAutoFocuses() {
        // Scripts/screenshots.sh needs the Today content, not the keyboard.
        #expect(CaptureFocusGate.decide(ready(demo: true)) == .idle)
    }

    /// Whatever the combination, the keyboard never rises while the app is off
    /// screen, locked, covered, or still in onboarding.
    @Test func focusNeverEscapesTheGate() {
        for bits in 0..<128 {
            let input = ready(
                active: bits & 1 != 0,
                locked: bits & 2 != 0,
                covered: bits & 4 != 0,
                onboarded: bits & 8 != 0,
                used: bits & 16 != 0,
                requested: bits & 32 != 0,
                demo: bits & 64 != 0
            )
            guard CaptureFocusGate.decide(input) == .focus else { continue }
            #expect(input.isSceneActive)
            #expect(!input.isLocked)
            #expect(!input.isCoveredByModal)
            #expect(input.hasCompletedOnboarding)
            // Either an explicit request, or the unspent one-shot auto-focus.
            #expect(input.isCaptureRequested || (!input.autoFocusUsed && !input.isDemoSeed))
        }
    }
}
