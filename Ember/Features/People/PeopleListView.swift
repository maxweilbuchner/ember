// PeopleListView.swift

import SwiftData
import SwiftUI

struct PeopleListView: View {
    @Query(sort: \Person.displayNameCache) private var people: [Person]
    @State private var showSettings = false
    @State private var showAddPeople = false

    private func people(in tier: CadenceTier) -> [Person] {
        people.filter { $0.tier == tier }
    }

    var body: some View {
        NavigationStack {
            Group {
                if people.isEmpty {
                    EmptyStateView(
                        systemImage: "person.2",
                        title: String(localized: "Your people live here"),
                        message: String(localized: "Add the friends and family you want to keep warm — a handful is plenty.")
                    )
                } else {
                    List {
                        ForEach(CadenceTier.allCases, id: \.self) { tier in
                            let tierPeople = people(in: tier)
                            if !tierPeople.isEmpty {
                                Section(tier.title) {
                                    ForEach(tierPeople) { person in
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
            .navigationTitle(String(localized: "People"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem {
                    Button {
                        showAddPeople = true
                    } label: {
                        Image(systemName: "plus")
                    }
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
