// PeopleListView.swift

import SwiftData
import SwiftUI

struct PeopleListView: View {
    @Environment(AppServices.self) private var services
    @Query(sort: \Person.displayNameCache) private var people: [Person]
    @State private var showSettings = false
    @State private var showAddPeople = false

    private var visiblePeople: [Person] {
        people.filter { !$0.isPlaceholder }
    }

    /// Grouped by keep-in-touch choice, so the partner sits in its own section
    /// instead of under a cadence that doesn't apply to them.
    private func people(in choice: KeepInTouch) -> [Person] {
        visiblePeople.filter { $0.keepInTouch == choice }
    }

    var body: some View {
        @Bindable var router = services.router
        NavigationStack {
            Group {
                if visiblePeople.isEmpty {
                    EmptyStateView(
                        systemImage: "person.2",
                        title: String(localized: "Your people live here"),
                        message: String(localized: "Add the friends and family you want to keep warm — a handful is plenty.")
                    )
                } else {
                    List {
                        ForEach(KeepInTouch.allCases, id: \.self) { choice in
                            let sectionPeople = people(in: choice)
                            if !sectionPeople.isEmpty {
                                Section(choice.title) {
                                    ForEach(sectionPeople) { person in
                                        NavigationLink {
                                            PersonDetailView(person: person)
                                        } label: {
                                            PersonRow(person: person)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .emberCanvas()
            #if DEBUG
            // Programmatic navigation for the DEBUG deep links (screenshot script).
            .navigationDestination(item: $router.detailPersonID.asIdentifiable) { target in
                if let person = people.first(where: { $0.id == target.id }) {
                    PersonDetailView(person: person)
                }
            }
            .onChange(of: router.settingsRequested) { _, requested in
                if requested {
                    showSettings = true
                    router.settingsRequested = false
                }
            }
            // The deep link can switch to this tab and request settings in the same
            // tick — before onChange is mounted — so check again on appear.
            .onAppear {
                if router.settingsRequested {
                    showSettings = true
                    router.settingsRequested = false
                }
            }
            #endif
            .navigationTitle(String(localized: "People"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(String(localized: "Settings"))
                }
                ToolbarItem {
                    Button {
                        showAddPeople = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(String(localized: "Add people"))
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showAddPeople) {
                AddPeopleSheet()
            }
        }
    }
}

private struct PersonRow: View {
    let person: Person

    var body: some View {
        HStack(spacing: 12) {
            PersonAvatarView(person: person, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(person.displayNameCache)
                    if person.isPartnerMode {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                if let last = person.interactions.max(by: { $0.date < $1.date }) {
                    // Neutral phrasing by design — elapsed time is never a deficit.
                    Text(NeutralPhrases.lastContact(channel: last.channel, note: last.note, date: last.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
