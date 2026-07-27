// EmberCaptureWidget.swift

import SwiftUI
import WidgetKit

/// The single lock-screen capture widget: a flame that deep-links straight into
/// the focused capture field (ember://capture). No data, no timeline — capture
/// must stay nearly free (spec §1.3).
@main
struct EmberCaptureWidgetBundle: WidgetBundle {
    var body: some Widget {
        EmberCaptureWidget()
    }
}

struct EmberCaptureWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EmberCapture", provider: CaptureProvider()) { _ in
            CaptureWidgetView()
        }
        .configurationDisplayName(String(localized: "Capture"))
        .description(String(localized: "Jot down what happened — straight into Ember."))
        .supportedFamilies([.accessoryCircular])
    }
}

nonisolated struct CaptureEntry: TimelineEntry {
    let date: Date
}

nonisolated struct CaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaptureEntry {
        CaptureEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (CaptureEntry) -> Void) {
        completion(CaptureEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CaptureEntry>) -> Void) {
        completion(Timeline(entries: [CaptureEntry(date: .now)], policy: .never))
    }
}

struct CaptureWidgetView: View {
    var body: some View {
        ZStack {
            Image(systemName: "flame.fill")
                .font(.title2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            Color.clear
        }
        .widgetURL(URL(string: "ember://capture"))
    }
}
