// SettingsView.swift

import Contacts
import ContactsUI
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var showContactPicker = false
    @State private var contactStatus = ContactService.authorizationStatus

    var body: some View {
        NavigationStack {
            List {
                Section(String(localized: "Contacts")) {
                    LabeledContent(String(localized: "Access"), value: contactStatusText)
                    if contactStatus == .notDetermined {
                        Button(String(localized: "Connect Contacts")) {
                            Task {
                                contactStatus = await services.contacts.requestAccess()
                            }
                        }
                    }
                    if contactStatus == .limited {
                        Button(String(localized: "Choose more contacts")) {
                            showContactPicker = true
                        }
                    }
                    Button(String(localized: "Refresh names now")) {
                        Task { await services.personSync.refreshAll() }
                    }
                }

                Section(String(localized: "Notifications")) {
                    NavigationLink(String(localized: "Nudges & birthdays")) {
                        NotificationSettingsView()
                    }
                }

                Section(String(localized: "Apple Intelligence")) {
                    LabeledContent(String(localized: "Suggestions & drafts"), value: services.modelAvailability.statusText)
                    if let explanation = services.modelAvailability.explanation {
                        Text(explanation)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(String(localized: "Privacy & data")) {
                    LabeledContent(String(localized: "App lock"), value: String(localized: "Coming soon"))
                    LabeledContent(String(localized: "Export"), value: String(localized: "Coming soon"))
                }

                Section(String(localized: "About")) {
                    LabeledContent(String(localized: "Version"), value: appVersion)
                    Text(String(localized: "No accounts. No servers. No analytics. Everything lives on this device."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(String(localized: "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .contactAccessPicker(isPresented: $showContactPicker) { _ in
                Task { await services.personSync.refreshAll() }
            }
            .onAppear {
                contactStatus = ContactService.authorizationStatus
                services.modelAvailability = .current
            }
        }
    }

    private var contactStatusText: String {
        switch contactStatus {
        case .authorized: String(localized: "Full access")
        case .limited: String(localized: "Selected contacts")
        case .denied, .restricted: String(localized: "Off — enable in Settings")
        case .notDetermined: String(localized: "Not connected")
        @unknown default: String(localized: "Unknown")
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        return version
    }
}
