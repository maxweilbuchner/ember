// NotificationSettingsView.swift

import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct NotificationSettingsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.openURL) private var openURL
    @Query private var settings: [NotificationSettings]
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        List {
            Section {
                Toggle(String(localized: "Weekly nudges"), isOn: nudgesBinding)
                Toggle(String(localized: "Birthdays & dates"), isOn: occasionAlertsBinding)
            } header: {
                Text(String(localized: "From Ember"))
            } footer: {
                Text(String(localized: "At most three nudges a week, each with context and a reason. Birthday and date alerts arrive the morning of, with a heads-up three days ahead. Turn either off and Ember stays quiet — your people, your notes, and the dates on Today are all still here."))
            }

            Section {
                LabeledContent(String(localized: "Notifications"), value: statusText)
                if authorizationStatus == .notDetermined {
                    Button(String(localized: "Allow notifications")) {
                        Task {
                            await requestAuthorization()
                        }
                    }
                } else if authorizationStatus == .denied {
                    Button(String(localized: "Open Settings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
            } header: {
                Text(String(localized: "iOS"))
            } footer: {
                if authorizationStatus == .denied {
                    Text(String(localized: "iOS is holding notifications back right now. Ember's switches above still apply inside the app."))
                }
            }
        }
        .emberCanvas()
        .navigationTitle(String(localized: "Nudges & birthdays"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshStatus() }
    }

    /// An absent row is the normal never-touched-it state and means both on;
    /// newest write wins if a duplicate ever slipped in.
    private var flags: NotificationFlags {
        guard let row = settings.max(by: { $0.updatedAt < $1.updatedAt }) else { return .allEnabled }
        return NotificationFlags(
            nudgesEnabled: row.nudgesEnabled,
            occasionAlertsEnabled: row.occasionAlertsEnabled
        )
    }

    private var nudgesBinding: Binding<Bool> {
        Binding(
            get: { flags.nudgesEnabled },
            set: { newValue in
                Task {
                    await askFirstIfNeeded(turningOn: newValue)
                    await services.setNudgesEnabled(newValue)
                }
            }
        )
    }

    private var occasionAlertsBinding: Binding<Bool> {
        Binding(
            get: { flags.occasionAlertsEnabled },
            set: { newValue in
                Task {
                    await askFirstIfNeeded(turningOn: newValue)
                    await services.setOccasionAlertsEnabled(newValue)
                }
            }
        )
    }

    /// Switching something on before iOS has ever been asked would leave the user
    /// with a live switch and silence, so the prompt comes first. The switches
    /// stay usable when iOS is denying: they still govern what Ember does in-app.
    private func askFirstIfNeeded(turningOn: Bool) async {
        guard turningOn, authorizationStatus == .notDetermined else { return }
        await requestAuthorization()
    }

    private func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
        await refreshStatus()
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
