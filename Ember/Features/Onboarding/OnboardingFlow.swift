// OnboardingFlow.swift

import SwiftData
import SwiftUI
import UserNotifications

/// Target: under two minutes. Value promise → Contacts permission → pick your
/// people into tiers (one optional partner) → notification permission. No account, ever.
struct OnboardingFlow: View {
    private enum Step {
        case welcome
        case contacts
        case pick
        case tiers
        case notifications
    }

    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var step: Step = .welcome
    @State private var drafts: [PersonDraft] = []

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .welcome:
                    welcome
                case .contacts:
                    contactsPermission
                case .pick:
                    PeoplePickerView(drafts: $drafts) {
                        step = drafts.isEmpty ? .notifications : .tiers
                    }
                case .tiers:
                    TierAssignmentView(drafts: $drafts) {
                        step = .notifications
                    }
                case .notifications:
                    notificationsPermission
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private var welcome: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "flame")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
            Text(String(localized: "Ember"))
                .font(.largeTitle.weight(.bold))
            Text(String(localized: "Keep the people you love warm. Ember remembers who matters, what you talked about, and quietly suggests when a message would land well."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            Text(String(localized: "Everything stays on this phone. No account, no cloud, no feed."))
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            Spacer()
            Button(String(localized: "Get started")) {
                step = .contacts
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 32)
        }
    }

    private var contactsPermission: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
            Text(String(localized: "Link your contacts"))
                .font(.title2.weight(.semibold))
            Text(String(localized: "Ember reads names, photos, and birthdays straight from Contacts — nothing is copied or uploaded. You can share all contacts or just a few."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            Spacer()
            VStack(spacing: 12) {
                Button(String(localized: "Connect Contacts")) {
                    Task {
                        await services.contacts.requestAccess()
                        step = .pick
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button(String(localized: "Not now")) {
                    step = .notifications
                }
                .foregroundStyle(.secondary)
            }
            .padding(.bottom, 32)
        }
    }

    private var notificationsPermission: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "bell.badge")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
            Text(String(localized: "Gentle nudges"))
                .font(.title2.weight(.semibold))
            Text(String(localized: "At most three suggestions a week, each with context and never a guilt trip. Silence is fine too."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            Spacer()
            VStack(spacing: 12) {
                Button(String(localized: "Enable nudges")) {
                    Task {
                        _ = try? await UNUserNotificationCenter.current()
                            .requestAuthorization(options: [.alert, .sound, .badge])
                        finish()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button(String(localized: "Maybe later")) {
                    finish()
                }
                .foregroundStyle(.secondary)
            }
            .padding(.bottom, 32)
        }
    }

    private func finish() {
        for draft in drafts {
            let person = Person(
                contactID: draft.contact.id,
                displayNameCache: draft.contact.displayName,
                tier: draft.tier,
                isPartnerMode: draft.isPartner
            )
            modelContext.insert(person)
        }
        try? modelContext.save()
        hasCompletedOnboarding = true
    }
}

nonisolated struct PersonDraft: Identifiable, Sendable, Equatable {
    var contact: ResolvedContact
    var tier: CadenceTier = .regular
    var isPartner: Bool = false

    var id: String { contact.id }
}
