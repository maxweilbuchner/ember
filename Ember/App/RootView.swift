// RootView.swift

import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        @Bindable var router = services.router
        TabView(selection: $router.selectedTab) {
            Tab(String(localized: "Today"), systemImage: "sun.horizon", value: AppTab.today) {
                TodayView()
            }
            Tab(String(localized: "People"), systemImage: "person.2", value: AppTab.people) {
                PeopleListView()
            }
            Tab(String(localized: "Journal"), systemImage: "book.closed", value: AppTab.journal) {
                JournalListView()
            }
        }
        .fontDesign(.rounded)
        .task {
            await services.startUp()
        }
        .onOpenURL { url in
            if let link = DeepLink(url: url) {
                services.router.handle(link)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, hasCompletedOnboarding else { return }
            Task { await services.becameActive() }
        }
        .fullScreenCover(isPresented: .constant(!hasCompletedOnboarding)) {
            OnboardingFlow()
        }
        .sheet(item: $router.composePersonID.asIdentifiable) { target in
            NavigationStack {
                PersonLookupView(personID: target.id)
            }
        }
    }
}

/// Wraps a bare UUID binding so it can drive `.sheet(item:)`.
nonisolated struct IdentifiableUUID: Identifiable, Equatable, Sendable {
    let id: UUID
}

extension Binding where Value == UUID? {
    @MainActor var asIdentifiable: Binding<IdentifiableUUID?> {
        Binding<IdentifiableUUID?>(
            get: { wrappedValue.map(IdentifiableUUID.init) },
            set: { wrappedValue = $0?.id }
        )
    }
}

/// Fetches a Person by UUID and opens Compose — the landing point of a
/// nudge notification tap.
struct PersonLookupView: View {
    @Query private var people: [Person]

    init(personID: UUID) {
        _people = Query(filter: #Predicate<Person> { $0.id == personID })
    }

    var body: some View {
        if let person = people.first {
            ComposeView(person: person)
        } else {
            EmptyStateView(
                systemImage: "person.crop.circle.badge.questionmark",
                title: String(localized: "Not here anymore"),
                message: String(localized: "This person is no longer in Ember.")
            )
        }
    }
}
