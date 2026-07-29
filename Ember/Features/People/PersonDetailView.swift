// PersonDetailView.swift

import SwiftData
import SwiftUI

struct PersonDetailView: View {
    @Bindable var person: Person
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var resolvedContact: ResolvedContact?
    @State private var checkedResolution = false
    @State private var showLogSheet = false
    @State private var showRelinkSheet = false
    @State private var confirmDelete = false
    @State private var newCommitmentText = ""
    @State private var newIdeaText = ""

    private var isUnresolvable: Bool {
        person.contactID != nil && checkedResolution && resolvedContact == nil
    }

    private var showsRelinkSection: Bool {
        #if DEBUG
        if DemoSeed.isActive { return false }
        #endif
        return person.contactID == nil || isUnresolvable
    }

    private var timeline: [TimelineItem] {
        let interactions = person.interactions.map(TimelineItem.interaction)
        let mentions = person.mentions.map(TimelineItem.mention)
        return (interactions + mentions).sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            headerSection
            if showsRelinkSection {
                relinkSection
            }
            Section {
                Button {
                    showLogSheet = true
                } label: {
                    Label(String(localized: "Log an interaction"), systemImage: "plus.bubble")
                }
            }
            commitmentsSection
            ideasSection
            timelineSection
        }
        .navigationTitle(person.displayNameCache)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem {
                Menu {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label(String(localized: "Remove from Ember"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showLogSheet) {
            InteractionLogSheet(person: person)
        }
        .sheet(isPresented: $showRelinkSheet) {
            RelinkContactSheet(person: person)
        }
        .confirmationDialog(
            String(localized: "Remove \(person.displayNameCache)? Their interactions, commitments, and ideas go too. Journal entries stay."),
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Remove"), role: .destructive) {
                modelContext.delete(person)
                try? modelContext.save()
                dismiss()
            }
        }
        .task(id: person.contactID) {
            checkedResolution = false
            if let contactID = person.contactID {
                resolvedContact = await services.contacts.resolve(contactID)
            } else {
                resolvedContact = nil
            }
            checkedResolution = true
        }
    }

    private var birthdayText: String? {
        guard let month = person.manualBirthdayMonth, let day = person.manualBirthdayDay else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = person.manualBirthdayYear != nil ? "MMMM d, yyyy" : "MMMM d"
        var components = DateComponents()
        components.month = month
        components.day = day
        components.year = person.manualBirthdayYear
        guard let date = Calendar.current.date(from: components) else { return nil }
        return formatter.string(from: date)
    }

    private var headerSection: some View {
        Section {
            HStack(spacing: 14) {
                PersonAvatarView(person: person, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(person.displayNameCache)
                        .font(.title3.weight(.semibold))
                    if let birthday = birthdayText {
                        Text("🎂 \(birthday)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let last = person.interactions.max(by: { $0.date < $1.date }) {
                        Text(NeutralPhrases.lastContact(channel: last.channel, note: last.note, date: last.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Picker(String(localized: "Cadence"), selection: $person.tier) {
                ForEach(CadenceTier.allCases, id: \.self) { tier in
                    Text(tier.title).tag(tier)
                }
            }
            Toggle(String(localized: "Partner"), isOn: partnerBinding)
        } footer: {
            if person.isPartnerMode {
                Text(String(localized: "Partners are never nudged about staying in touch — birthdays, commitments, and ideas still show up."))
            }
        }
    }

    private var partnerBinding: Binding<Bool> {
        Binding(
            get: { person.isPartnerMode },
            set: { newValue in
                if newValue {
                    // Only one partner: quietly clear the flag elsewhere.
                    let others = (try? modelContext.fetch(FetchDescriptor<Person>())) ?? []
                    for other in others where other.isPartnerMode && other.id != person.id {
                        other.isPartnerMode = false
                    }
                }
                person.isPartnerMode = newValue
                try? modelContext.save()
            }
        )
    }

    private var relinkSection: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "link.badge.plus")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Not linked to a contact"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Everything here is safe. Link a contact to see their photo and birthday again."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button(String(localized: "Link contact")) {
                showRelinkSheet = true
            }
        }
    }

    private var commitmentsSection: some View {
        Section(String(localized: "Commitments")) {
            ForEach(person.commitments.sorted { $0.createdAt > $1.createdAt }) { commitment in
                Button {
                    commitment.isDone.toggle()
                    try? modelContext.save()
                } label: {
                    HStack {
                        Image(systemName: commitment.isDone ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(commitment.isDone ? Color.accentColor : Color.secondary)
                        Text(commitment.text)
                            .strikethrough(commitment.isDone)
                            .foregroundStyle(commitment.isDone ? .secondary : .primary)
                    }
                }
            }
            TextField(String(localized: "You said you'd…"), text: $newCommitmentText)
                .onSubmit {
                    let trimmed = newCommitmentText.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    modelContext.insert(Commitment(person: person, text: trimmed))
                    try? modelContext.save()
                    newCommitmentText = ""
                }
        }
    }

    private var ideasSection: some View {
        Section(String(localized: "Ideas")) {
            ForEach(person.ideas.sorted { $0.createdAt > $1.createdAt }) { idea in
                Button {
                    idea.isDone.toggle()
                    try? modelContext.save()
                } label: {
                    HStack {
                        Image(systemName: idea.isDone ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(idea.isDone ? Color.accentColor : Color.secondary)
                        Text(idea.text)
                            .strikethrough(idea.isDone)
                            .foregroundStyle(idea.isDone ? .secondary : .primary)
                    }
                }
            }
            TextField(String(localized: "Gift idea, topic to raise…"), text: $newIdeaText)
                .onSubmit {
                    let trimmed = newIdeaText.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    modelContext.insert(Idea(person: person, text: trimmed))
                    try? modelContext.save()
                    newIdeaText = ""
                }
        }
    }

    private var timelineSection: some View {
        Section(String(localized: "Timeline")) {
            if timeline.isEmpty {
                Text(String(localized: "Interactions and journal mentions will gather here."))
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            ForEach(timeline.prefix(50)) { item in
                switch item {
                case .interaction(let interaction):
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: interaction.channel.symbolName)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(interaction.note?.isEmpty == false ? interaction.note! : interaction.channel.title)
                            Text(NeutralPhrases.phrase(for: interaction.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                case .mention(let entry):
                    NavigationLink {
                        EntryDetailView(entry: entry)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "book.closed")
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.previewLine)
                                    .lineLimit(2)
                                Text(NeutralPhrases.phrase(for: entry.date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

private enum TimelineItem: Identifiable {
    case interaction(Interaction)
    case mention(Entry)

    var id: UUID {
        switch self {
        case .interaction(let interaction): interaction.id
        case .mention(let entry): entry.id
        }
    }

    var date: Date {
        switch self {
        case .interaction(let interaction): interaction.date
        case .mention(let entry): entry.date
        }
    }
}
