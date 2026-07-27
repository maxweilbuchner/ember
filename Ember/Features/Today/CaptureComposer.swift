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
        .onAppear { isFocused = true }
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
        text = ""
        isFocused = true
    }
}
