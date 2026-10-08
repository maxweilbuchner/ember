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
    @State private var adding: AddField?
    @State private var headerScrolledAway = false
    @FocusState private var focusedField: AddField?

    private enum AddField: Hashable {
        case commitment, idea
    }

    private var isUnresolvable: Bool {
        person.contactID != nil && checkedResolution && resolvedContact == nil
    }

    private var showsRelinkSection: Bool {
        #if DEBUG
        if DemoSeed.isActive { return false }
        #endif
        return person.contactID == nil || isUnresolvable
    }

    /// Interactions and journal mentions, newest first. An interaction that was
    /// logged from an entry is the same moment as that entry's mention, so it
    /// shows once — as the entry, wearing the interaction's channel icon.
    private var timeline: [TimelineItem] {
        let mentionIDs = Set(person.mentions.map(\.id))
        let interactions = person.interactions
            .filter { interaction in
                guard let sourceID = interaction.sourceEntryID else { return true }
                return !mentionIDs.contains(sourceID)
            }
            .map(TimelineItem.interaction)
        let mentions = person.mentions.map(TimelineItem.mention)
        return (interactions + mentions).sorted { $0.date > $1.date }
    }

    private var channelByEntryID: [UUID: Channel] {
        var result: [UUID: Channel] = [:]
        for interaction in person.interactions {
            if let sourceID = interaction.sourceEntryID {
                result[sourceID] = interaction.channel
            }
        }
        return result
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
        // Most actionable first: who they are and what to do, then what you
        // owe them, then dates and labels, then the history.
        List {
            headerSection
            if showsRelinkSection {
                relinkSection
            }
            if person.commitments.isEmpty && person.ideas.isEmpty {
                // Nothing noted yet: two quiet add rows, not two empty sections.
                Section {
                    commitmentAdder
                    ideaAdder
                }
            } else {
                commitmentsSection
                ideasSection
            }
            datesSection
            relationsSection
            keepInTouchSection
            timelineSection
        }
        .emberCanvas()
        // The header card already names them; the bar only does once it has
        // scrolled away (Contacts-style). The title still labels the back button.
        .navigationTitle(person.displayNameCache)
        .navigationBarTitleDisplayMode(.inline)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 90
        } action: { _, scrolledAway in
            withAnimation(EmberTheme.calm) { headerScrolledAway = scrolledAway }
        }
        .onChange(of: focusedField) { _, field in
            // Leaving an empty add field folds it back into its add row.
            if field == nil { adding = nil }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(person.displayNameCache)
                    .font(.headline)
                    .lineLimit(1)
                    .opacity(headerScrolledAway ? 1 : 0)
                    .accessibilityHidden(!headerScrolledAway)
            }
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
            HStack(alignment: .center, spacing: 14) {
                PersonAvatarView(person: person, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(person.displayNameCache)
                        .font(.title3.weight(.semibold))
                    if let relationChip {
                        EmberChip(text: relationChip.text, systemImage: relationChip.systemImage)
                    }
                    if let occasionLine {
                        Text(occasionLine)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                    } else if let last = person.interactions.max(by: { $0.date < $1.date }) {
                        Text(NeutralPhrases.lastContact(channel: last.channel, note: last.note, date: last.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: EmberTheme.spacingS) {
                Button {
                    services.router.composePersonID = person.id
                } label: {
                    actionLabel(String(localized: "Message"), systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    showLogSheet = true
                } label: {
                    actionLabel(String(localized: "Log"), systemImage: "plus.bubble")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(String(localized: "Log an interaction"))
            }
            // Bordered styles keep these two separate tap targets inside the
            // List row (a plain-style row would fire both at once).
            .listRowSeparator(.hidden)
        }
    }

    /// An explicit HStack, not a Label: inside a List a Label takes the row's
    /// icon-column layout, which pulls icon and title apart.
    private func actionLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.body.weight(.medium))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    /// The nearest birthday or date inside the alert window — the best reason
    /// to reach out, so it takes the header's context line ("Birthday today 🎂").
    private var occasionLine: String? {
        var soonest: (days: Int, text: String)?
        func consider(_ days: Int?, _ label: String) {
            guard let days, days <= NudgeScoring.birthdayWindowDays,
                  days < (soonest?.days ?? .max) else { return }
            soonest = (days, days == 0
                ? String(localized: "\(label) today 🎂")
                : String(localized: "\(label) \(NeutralPhrases.upcoming(daysAway: days))"))
        }
        if let birthday = effectiveBirthday {
            consider(BirthdayMath.daysUntilNextBirthday(birthday, from: .now), String(localized: "Birthday"))
        }
        for customDate in person.customDates {
            consider(
                BirthdayMath.daysUntilNextBirthday(DateComponents(month: customDate.month, day: customDate.day), from: .now),
                customDate.label
            )
        }
        return soonest?.text
    }

    /// Set once, rarely changed — so it sits below the things you act on.
    private var keepInTouchSection: some View {
        Section {
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
        Section {
            ForEach(openFirst(person.commitments, isDone: \.isDone, createdAt: \.createdAt)) { commitment in
                checklistRow(text: commitment.text, isDone: commitment.isDone) {
                    commitment.isDone.toggle()
                    try? modelContext.save()
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    deleteButton { modelContext.delete(commitment) }
                }
            }
            commitmentAdder
        } header: {
            if !person.commitments.isEmpty {
                Text(String(localized: "Commitments"))
            }
        }
    }

    private var ideasSection: some View {
        Section {
            ForEach(openFirst(person.ideas, isDone: \.isDone, createdAt: \.createdAt)) { idea in
                checklistRow(text: idea.text, isDone: idea.isDone) {
                    idea.isDone.toggle()
                    try? modelContext.save()
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    deleteButton { modelContext.delete(idea) }
                }
            }
            ideaAdder
        } header: {
            if !person.ideas.isEmpty {
                Text(String(localized: "Ideas"))
            }
        }
    }

    private var commitmentAdder: some View {
        addRow(
            .commitment,
            title: String(localized: "Add a commitment"),
            systemImage: "checklist",
            prompt: String(localized: "You said you'd…"),
            text: $newCommitmentText
        ) { text in
            modelContext.insert(Commitment(person: person, text: text))
        }
    }

    private var ideaAdder: some View {
        addRow(
            .idea,
            title: String(localized: "Add an idea"),
            systemImage: "lightbulb",
            prompt: String(localized: "Gift idea, topic to raise…"),
            text: $newIdeaText
        ) { text in
            modelContext.insert(Idea(person: person, text: text))
        }
    }

    /// A quiet "Add …" row (like "Add a date") that becomes a text field on
    /// tap. Submitting saves and keeps the field open for the next one.
    @ViewBuilder
    private func addRow(
        _ field: AddField,
        title: String,
        systemImage: String,
        prompt: String,
        text: Binding<String>,
        insert: @escaping (String) -> Void
    ) -> some View {
        if adding == field {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)
                TextField(prompt, text: text)
                    .focused($focusedField, equals: field)
                    .submitLabel(.done)
                    .onSubmit {
                        let trimmed = text.wrappedValue.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else {
                            adding = nil
                            return
                        }
                        insert(trimmed)
                        try? modelContext.save()
                        text.wrappedValue = ""
                        focusedField = field
                    }
            }
        } else {
            Button {
                adding = field
                focusedField = field
            } label: {
                Label(title, systemImage: systemImage)
            }
        }
    }

    /// Open items first (newest on top), finished ones after — so the list
    /// reads as what's left, not as a log.
    private func openFirst<Item>(
        _ items: [Item],
        isDone: KeyPath<Item, Bool>,
        createdAt: KeyPath<Item, Date>
    ) -> [Item] {
        items.sorted { lhs, rhs in
            if lhs[keyPath: isDone] != rhs[keyPath: isDone] {
                return !lhs[keyPath: isDone]
            }
            return lhs[keyPath: createdAt] > rhs[keyPath: createdAt]
        }
    }

    private func checklistRow(text: String, isDone: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isDone ? Color.accentColor : Color.secondary)
                // Explicit Colors: a hierarchical .primary inside a Button
                // resolves to the tint, which turned every item orange.
                Text(text)
                    .strikethrough(isDone)
                    .foregroundStyle(isDone ? Color.secondary : Color.primary)
            }
        }
        .accessibilityAddTraits(isDone ? .isSelected : [])
    }

    private func deleteButton(_ delete: @escaping () -> Void) -> some View {
        Button(role: .destructive) {
            delete()
            try? modelContext.save()
        } label: {
            Label(String(localized: "Delete"), systemImage: "trash")
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
                    // A mistaken log shouldn't be permanent — it feeds the
                    // nudge engine's sense of when you were last in touch.
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        deleteButton { modelContext.delete(interaction) }
                    }
                case .mention(let entry):
                    NavigationLink {
                        EntryDetailView(entry: entry)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            if let channel = channelByEntryID[entry.id] {
                                Image(systemName: channel.symbolName)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 22)
                                    .accessibilityLabel(channel.title)
                            } else {
                                Image(systemName: "book.closed")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22)
                                    .accessibilityLabel(String(localized: "Journal mention"))
                            }
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
