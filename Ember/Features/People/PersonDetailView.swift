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
    @State private var meRelationLabel: String?
    @State private var relatedLinks: [RelationLink] = []
    @State private var showLogSheet = false
    @State private var showRelinkSheet = false
    @State private var showBirthdayEditor = false
    @State private var showCustomDateSheet = false
    @State private var showMergeSheet = false
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

    /// Canonical precedence: the linked contact's birthday wins, manual fills in.
    private var effectiveBirthday: DateComponents? {
        BirthdayResolution.effectiveBirthday(contact: resolvedContact?.birthday, manual: person.manualBirthday)
    }

    /// The manual fields are editable exactly when they'd be the effective source;
    /// a contact-provided birthday is edited in Contacts, not here.
    private var birthdayIsEditable: Bool {
        person.contactID == nil || (checkedResolution && resolvedContact?.birthday == nil)
    }

    var body: some View {
        if person.isDeleted || person.modelContext == nil {
            // The person was just removed (delete/anonymize/merge). Render
            // nothing while the navigation stack unwinds — touching any
            // attribute of a detached @Model crashes.
            Color.clear
        } else {
            detailList
        }
    }

    private var detailList: some View {
        List {
            headerSection
            datesSection
            relationsSection
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
        .emberCanvas()
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
                .accessibilityLabel(String(localized: "More options"))
            }
        }
        .sheet(isPresented: $showLogSheet) {
            InteractionLogSheet(person: person)
        }
        .sheet(isPresented: $showRelinkSheet) {
            RelinkContactSheet(person: person, onMerged: { dismiss() })
        }
        .sheet(isPresented: $showMergeSheet) {
            MergePersonSheet(source: person, onFinished: { dismiss() })
        }
        .sheet(isPresented: $showBirthdayEditor, onDismiss: {
            // A birthday may have just been written to the contact card; the
            // resolved copy is stale until we re-read it.
            Task { await reloadResolvedContact() }
        }) {
            BirthdayEditorSheet(person: person)
        }
        .sheet(isPresented: $showCustomDateSheet) {
            CustomDateSheet(person: person)
        }
        .alert(
            String(localized: "Remove \(person.displayNameCache)?"),
            isPresented: $confirmDelete
        ) {
            if person.mentions.isEmpty {
                Button(String(localized: "Remove"), role: .destructive) {
                    removeCompletely()
                }
            } else {
                Button(String(localized: "Anonymize mentions"), role: .destructive) {
                    anonymize()
                }
                Button(String(localized: "Merge into another person…")) {
                    showMergeSheet = true
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(removalMessage)
        }
        .task(id: person.contactID) {
            await reloadResolvedContact()
            await loadRelations()
        }
    }

    private func reloadResolvedContact() async {
        checkedResolution = false
        if let contactID = person.contactID {
            resolvedContact = await services.contacts.resolve(contactID)
        } else {
            resolvedContact = nil
        }
        checkedResolution = true
    }

    private var removalMessage: String {
        if person.mentions.isEmpty {
            return String(localized: "Their interactions, commitments, ideas, and dates go too. Journal entries stay.")
        }
        return NeutralPhrases.journalAppearances(count: person.mentions.count)
            + " "
            + String(localized: "Anonymizing shows \"Someone\" in place of their name — that can't be undone. Merging moves everything to another person. Your journal text stays as written either way.")
    }

    private func removeCompletely() {
        let personID = person.id
        modelContext.delete(person)
        try? modelContext.save()
        Task { await services.personRemoved(personID) }
        dismiss()
    }

    private func anonymize() {
        let personID = person.id
        PersonMerge.anonymize(person, context: modelContext)
        Task { await services.personRemoved(personID) }
        dismiss()
    }

    /// Relation labels are derived live from Contacts (never stored): the user's
    /// own card names this person's relation to them; this person's card names
    /// their own related people, cross-linked to Ember people by name.
    private func loadRelations() async {
        let people = ((try? modelContext.fetch(FetchDescriptor<Person>())) ?? [])
            .map { RelationResolver.candidate(personID: $0.id, displayName: $0.displayNameCache) }
        let meRelations = await services.contacts.meContact()?.relations ?? []
        meRelationLabel = RelationResolver.labelForPerson(
            personID: person.id,
            meRelations: meRelations,
            people: people
        )
        relatedLinks = RelationResolver.related(
            relations: resolvedContact?.relations ?? [],
            people: people,
            excludingPersonID: person.id
        )
    }

    private var headerSection: some View {
        Section {
            HStack(spacing: 14) {
                PersonAvatarView(person: person, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(person.displayNameCache)
                            .font(.title3.weight(.semibold))
                        if let relationChip {
                            EmberChip(text: relationChip.text, systemImage: relationChip.systemImage)
                        }
                    }
                    if let last = person.interactions.max(by: { $0.date < $1.date }) {
                        Text(NeutralPhrases.lastContact(channel: last.channel, note: last.note, date: last.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            KeepInTouchPicker(selection: keepInTouchBinding)
        } footer: {
            Text(person.keepInTouch.explanation)
        }
    }

    /// The header chip: the relation label when there is one, with the ♥ when
    /// they're the partner; "Partner" alone when partner mode has no label.
    /// Partner mode drives the heart, never the other way round (§6.4).
    private var relationChip: (text: String, systemImage: String)? {
        let label = meRelationLabel ?? person.manualRelation?.title
        if person.isPartnerMode {
            return (text: label ?? KeepInTouch.partner.title, systemImage: "heart.fill")
        }
        return label.map { (text: $0, systemImage: "person.2") }
    }

    private var datesSection: some View {
        Section {
            if let birthday = effectiveBirthday {
                let row = HStack(spacing: 10) {
                    Image(systemName: "gift")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22)
                    Text(String(localized: "Birthday"))
                    Spacer()
                    if let daysAway = BirthdayMath.daysUntilNextBirthday(birthday, from: .now),
                       daysAway <= NudgeScoring.birthdayWindowDays {
                        EmberChip(text: daysAway == 0
                            ? String(localized: "today 🎂")
                            : NeutralPhrases.upcoming(daysAway: daysAway))
                    }
                    Text(birthdayLabel(birthday))
                        .foregroundStyle(.secondary)
                }
                if birthdayIsEditable {
                    Button {
                        showBirthdayEditor = true
                    } label: {
                        row
                    }
                    .foregroundStyle(.primary)
                } else {
                    row
                }
            } else if birthdayIsEditable {
                Button {
                    showBirthdayEditor = true
                } label: {
                    Label(String(localized: "Add birthday"), systemImage: "gift")
                }
            }
            ForEach(person.customDates.sorted { $0.createdAt < $1.createdAt }) { customDate in
                customDateRow(customDate)
            }
            Button {
                showCustomDateSheet = true
            } label: {
                Label(String(localized: "Add a date"), systemImage: "calendar.badge.plus")
            }
        } header: {
            Text(String(localized: "Dates"))
        } footer: {
            if !birthdayIsEditable && effectiveBirthday != nil {
                Text(String(localized: "From Contacts"))
            }
        }
    }

    private func customDateRow(_ customDate: CustomDate) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            Text(customDate.label)
            Spacer()
            if let daysAway = BirthdayMath.daysUntilNextBirthday(
                DateComponents(month: customDate.month, day: customDate.day), from: .now
            ), daysAway <= NudgeScoring.birthdayWindowDays {
                EmberChip(text: NeutralPhrases.upcoming(daysAway: daysAway))
            }
            Text(birthdayLabel(customDate.components))
                .foregroundStyle(.secondary)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                modelContext.delete(customDate)
                try? modelContext.save()
            } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
        }
    }

    private func birthdayLabel(_ birthday: DateComponents) -> String {
        var components = birthday
        let hasYear = birthday.year != nil
        components.year = birthday.year ?? 2000 // leap reference year so Feb 29 renders
        guard let date = Calendar.current.date(from: components) else { return "" }
        return hasYear
            ? date.formatted(.dateTime.month(.wide).day().year())
            : date.formatted(.dateTime.month(.wide).day())
    }

    @ViewBuilder
    private var relationsSection: some View {
        // Hidden entirely when there's nothing to show and nothing to set:
        // the me-card label already appears as the header chip.
        if !relatedLinks.isEmpty || meRelationLabel == nil {
            Section {
                ForEach(relatedLinks) { link in
                    if let linkedID = link.linkedPersonID, let target = fetchPerson(linkedID) {
                        NavigationLink {
                            PersonDetailView(person: target)
                        } label: {
                            relationRow(link)
                        }
                    } else {
                        relationRow(link)
                    }
                }
                if meRelationLabel == nil {
                    Picker(String(localized: "Relation to you"), selection: manualRelationBinding) {
                        Text(String(localized: "None")).tag(RelationKind?.none)
                        ForEach(manualRelationChoices, id: \.self) { kind in
                            Text(kind.title).tag(RelationKind?.some(kind))
                        }
                    }
                }
            } header: {
                Text(String(localized: "Relations"))
            } footer: {
                if !relatedLinks.isEmpty {
                    Text(String(localized: "From their contact card."))
                }
            }
        }
    }

    private func relationRow(_ link: RelationLink) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.2")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(link.name)
            Spacer()
            Text(link.localizedLabel)
                .foregroundStyle(.secondary)
        }
    }

    private func fetchPerson(_ id: UUID) -> Person? {
        let descriptor = FetchDescriptor<Person>(predicate: #Predicate { $0.id == id })
        return (try? modelContext.fetch(descriptor))?.first
    }

    /// Partner is chosen once, under Keep in touch — so the manual label list
    /// doesn't offer a second, disconnected "Partner"/"Spouse". A label set
    /// before this change stays selectable so it's never silently dropped.
    private var manualRelationChoices: [RelationKind] {
        RelationKind.allCases.filter { !$0.isPartnerLike || $0 == person.manualRelation }
    }

    private var manualRelationBinding: Binding<RelationKind?> {
        Binding(
            get: { person.manualRelation },
            set: { newValue in
                person.manualRelation = newValue
                try? modelContext.save()
            }
        )
    }

    private var keepInTouchBinding: Binding<KeepInTouch> {
        Binding(
            get: { person.keepInTouch },
            set: { KeepInTouchAssignment.apply($0, to: person, context: modelContext) }
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
