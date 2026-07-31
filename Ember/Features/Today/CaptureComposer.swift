// CaptureComposer.swift

import SwiftData
import SwiftUI

/// The capture field. Cold start to typing must stay under a second — the field
/// focuses itself as soon as the app is genuinely on screen, and saving keeps
/// focus so several entries can be logged back-to-back.
struct CaptureComposer: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @FocusState private var isFocused: Bool
    @State private var text = ""
    @State private var autoFocusUsed = false
    @State private var saveCount = 0

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            TextField(String(localized: "What happened?"), text: $text, axis: .vertical)
                .lineLimit(2...8)
                .focused($isFocused)
                .padding(14)
                .emberCardSurface()

            if !trimmedText.isEmpty {
                Button(String(localized: "Save")) {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .transition(.opacity)
            }
        }
        .animation(EmberTheme.calm, value: trimmedText.isEmpty)
        .sensoryFeedback(.success, trigger: saveCount)
        .toolbar {
            // Standard iOS pattern (Notes): a nav-bar Done while editing.
            // A keyboard-toolbar item is wrong here — iOS 26 docks it as a
            // floating pill that collides with the tab bar.
            if isFocused {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Done")) {
                        isFocused = false
                    }
                }
            }
        }
        // The keyboard may only come up once the app is actually on screen:
        // focusing during the first layout pass raised it behind the lock
        // screen, the onboarding cover and a nudge's Compose sheet (GH #12).
        // `initial: true` covers "the gate is already open on appear"; the
        // change path covers "it opens later" — unlock, sheet dismissed,
        // onboarding finished. Returning from another tab must not steal focus
        // back, which is what `autoFocusUsed` latches.
        .onChange(of: focusInput, initial: true) { _, input in
            switch CaptureFocusGate.decide(input) {
            case .focus:
                autoFocusUsed = true
                if input.isCaptureRequested {
                    services.router.captureRequested = false
                }
                isFocused = true
            case .cancelAutoFocus:
                autoFocusUsed = true
            case .wait, .idle:
                break
            }
        }
    }

    private var focusInput: CaptureFocusGate.Input {
        CaptureFocusGate.Input(
            isSceneActive: scenePhase == .active,
            isLocked: services.security.isLocked,
            isCoveredByModal: services.router.composePersonID != nil,
            hasCompletedOnboarding: hasCompletedOnboarding,
            autoFocusUsed: autoFocusUsed,
            isCaptureRequested: services.router.captureRequested,
            isDemoSeed: Self.isDemoSeed
        )
    }

    private static var isDemoSeed: Bool {
        #if DEBUG
        return DemoSeed.isActive
        #else
        return false
        #endif
    }

    private func save() {
        let entry = Entry(text: trimmedText)
        modelContext.insert(entry)
        try? modelContext.save()
        let entryID = entry.id
        let entryText = entry.text
        let services = services
        Task { await services.extractEntry(id: entryID, text: entryText) }
        saveCount += 1
        text = ""
        // Drop focus so the saved entry and its extraction chips are visible —
        // tapping the field again is one tap if there's more to capture.
        isFocused = false
    }
}
