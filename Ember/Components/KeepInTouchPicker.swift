// KeepInTouchPicker.swift

import SwiftUI

/// The one control for cadence + partner. Segmented while sorting new people,
/// a menu row on a person's page — same choices, same words, same rule.
struct KeepInTouchPicker: View {
    @Binding var selection: KeepInTouch
    var choices: [KeepInTouch] = KeepInTouch.allCases
    var segmented = false

    var body: some View {
        if segmented {
            picker
                .pickerStyle(.segmented)
                .labelsHidden()
        } else {
            picker
                .pickerStyle(.menu)
        }
    }

    private var picker: some View {
        Picker(String(localized: "Keep in touch"), selection: $selection) {
            ForEach(choices, id: \.self) { choice in
                if !segmented, let systemImage = choice.systemImage {
                    Label(choice.title, systemImage: systemImage)
                        .tag(choice)
                } else {
                    Text(choice.title)
                        .tag(choice)
                }
            }
        }
    }
}
