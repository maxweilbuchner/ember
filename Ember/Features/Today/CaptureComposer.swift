// CaptureComposer.swift

import SwiftData
import SwiftUI

/// The capture field. Cold start to typing must stay under a second — the field
/// focuses itself on appear, and saving keeps focus so several entries can be
/// logged back-to-back.
struct CaptureComposer: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @FocusState private var isFocused: Bool
    @State private var text = ""
    @State private var hasAutoFocused = false

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            TextField(String(localized: "What happened?"), text: $text, axis: .vertical)
                .lineLimit(2...8)
                .focused($isFocused)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))

            if !trimmedText.isEmpty {
                Button(String(localized: "Save")) {
                    save()
                }
                .buttonStyle(.borderedProminent)
            }
        }
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
        .onAppear {
            // Auto-focus only on first appearance (cold start to typing < 1s);
            // returning from another tab must not steal focus back.
            if !hasAutoFocused {
                hasAutoFocused = true
                #if DEBUG
                // Screenshot runs need the Today content, not the keyboard.
                if DemoSeed.isActive { return }
                #endif
                isFocused = true
            }
        }
        .onChange(of: services.router.captureRequested) { _, requested in
            if requested {
                isFocused = true
                services.router.captureRequested = false
            }
        }
    }

    private func save() {
        let entry = Entry(text: trimmedText)
        modelContext.insert(entry)
        try? modelContext.save()
        let entryID = entry.id
        let entryText = entry.text
        let services = services
        Task { await services.extractEntry(id: entryID, text: entryText) }
        text = ""
        // Drop focus so the saved entry and its extraction chips are visible —
        // tapping the field again is one tap if there's more to capture.
        isFocused = false
    }
}
