// NotificationSettingsView.swift

import SwiftUI
import UIKit
import UserNotifications

struct NotificationSettingsView: View {
    @Environment(\.openURL) private var openURL
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        List {
            Section {
                LabeledContent(String(localized: "Notifications"), value: statusText)
                if authorizationStatus == .notDetermined {
                    Button(String(localized: "Enable nudges")) {
                        Task {
                            _ = try? await UNUserNotificationCenter.current()
                                .requestAuthorization(options: [.alert, .sound, .badge])
                            await refreshStatus()
                        }
                    }
                } else if authorizationStatus == .denied {
                    Button(String(localized: "Open Settings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
            } footer: {
                Text(String(localized: "Ember sends at most three nudges a week, each with context and a reason. Birthday reminders arrive the morning of, with a heads-up three days ahead for planning."))
            }
        }
        .navigationTitle(String(localized: "Nudges & birthdays"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshStatus() }
    }

    private var statusText: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: String(localized: "On")
        case .denied: String(localized: "Off")
        case .notDetermined: String(localized: "Not set up")
        @unknown default: String(localized: "Unknown")
        }
    }

    private func refreshStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}
