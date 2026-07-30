// OnboardingFlow.swift

import SwiftData
import SwiftUI
import UserNotifications

/// Target: under two minutes. Value promise → Contacts permission → pick your
/// people into tiers (one optional partner) → notification permission. No account, ever.
struct OnboardingFlow: View {
    private enum Step: Hashable {
        case contacts
        case pick
        case tiers
        case notifications
    }

    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    /// Welcome is the stack root; pushing steps gives native back navigation,
    /// so a re-pick is always one swipe away.
    @State private var path: [Step] = []
    @State private var drafts: [PersonDraft] = []

    var body: some View {
        NavigationStack(path: $path) {
            welcome
                .emberCanvas()
                .navigationDestination(for: Step.self) { step in
                    stepView(step)
                        .emberCanvas()
                }
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private func stepView(_ step: Step) -> some View {
        switch step {
        case .contacts:
            contactsPermission
        case .pick:
            PeoplePickerView(
                drafts: $drafts,
                onContinue: {
                    path.append(drafts.isEmpty ? .notifications : .tiers)
                },
                barAccessory: {
                    progressCaption(2)
                }
            )
        case .tiers:
            TierAssignmentView(drafts: $drafts, barCaption: progressText(3)) {
                path.append(.notifications)
            }
        case .notifications:
            notificationsPermission
        }
    }

    private func progressText(_ step: Int) -> String {
        String(localized: "Step \(step) of 4")
    }

    private func progressCaption(_ step: Int) -> some View {
        Text(progressText(step))
            .font(.footnote)
            .foregroundStyle(.tertiary)
    }

    private var welcome: some View {
        VStack(spacing: EmberTheme.spacingXL) {
            Spacer()
            HeroHeader(
                systemImage: "flame",
                title: String(localized: "Ember"),
                message: String(localized: "Keep the people you love warm. Ember remembers who matters, what you talked about, and quietly suggests when a message would land well."),
                style: .brand
            )
            Text(String(localized: "Everything stays on this phone. No account, no cloud, no feed."))
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, EmberTheme.spacingXL)
            Spacer()
        }
        .safeAreaInset(edge: .bottom) {
            PinnedBottomBar {
                Button(String(localized: "Get started")) {
                    path.append(.contacts)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private var contactsPermission: some View {
        VStack {
            Spacer()
            HeroHeader(
                systemImage: "person.crop.circle.badge.checkmark",
                title: String(localized: "Link your contacts"),
                message: String(localized: "Ember reads names, photos, and birthdays straight from Contacts — nothing is copied or uploaded. You can share all contacts or just a few.")
            )
            Spacer()
        }
        .safeAreaInset(edge: .bottom) {
            PinnedBottomBar {
                progressCaption(1)
                Button(String(localized: "Connect Contacts")) {
                    Task {
                        await services.contacts.requestAccess()
                        path.append(.pick)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button(String(localized: "Not now")) {
                    path.append(.notifications)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private var notificationsPermission: some View {
        VStack {
            Spacer()
            HeroHeader(
                systemImage: "bell.badge",
                title: String(localized: "Gentle nudges"),
                message: String(localized: "At most three suggestions a week, each with context and never a guilt trip. Silence is fine too.")
            )
            Spacer()
        }
        .safeAreaInset(edge: .bottom) {
            PinnedBottomBar {
                progressCaption(4)
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
