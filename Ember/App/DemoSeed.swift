// DemoSeed.swift

#if DEBUG
import Foundation
import SwiftData

/// Screenshot fixture, active only when the app is launched with `--demo-seed`
/// (see `Scripts/screenshots.sh`). Wipes the store and installs a small fictional
/// dataset with fixed person UUIDs so the script can deep-link to exact screens.
/// `--demo-variant chips` swaps the pending-nudges layout for a pending entry
/// with extraction chips. Compiled out of Release builds entirely.
enum DemoSeed {
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("--demo-seed")
    }

    static var variant: String? {
        argumentValue(after: "--demo-variant")
    }

    /// Deep link applied after launch (RootView). `simctl openurl` would show the
    /// system "Open in Ember?" dialog, which nothing can tap in a scripted run.
    static var linkURL: URL? {
        argumentValue(after: "--demo-link").flatMap(URL.init)
    }

    private static func argumentValue(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    // Fixed IDs — the screenshot script deep-links ember://person/… and ember://compose/…
    static let juliaID = UUID(uuidString: "DE300001-0000-4000-8000-000000000001")!
    static let annaID = UUID(uuidString: "DE300002-0000-4000-8000-000000000002")!
    static let jonasID = UUID(uuidString: "DE300003-0000-4000-8000-000000000003")!
    static let priyaID = UUID(uuidString: "DE300004-0000-4000-8000-000000000004")!
    static let tomID = UUID(uuidString: "DE300005-0000-4000-8000-000000000005")!
    static let maraID = UUID(uuidString: "DE300006-0000-4000-8000-000000000006")!
    static let pendingEntryID = UUID(uuidString: "DE300010-0000-4000-8000-000000000010")!

    static func apply(container: ModelContainer, services: AppServices) {
        let context = container.mainContext
        wipe(context)

        let calendar = Calendar.current
        let now = Date.now
        func daysAgo(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: -days, to: now) ?? now
        }
        let birthdayDate = calendar.date(byAdding: .day, value: 3, to: now) ?? now
        let birthdayComponents = calendar.dateComponents([.month, .day], from: birthdayDate)

        func addPerson(_ id: UUID, _ name: String, _ tier: CadenceTier, partner: Bool = false, birthday: DateComponents? = nil) -> Person {
            let person = Person(displayNameCache: name, tier: tier, isPartnerMode: partner, manualBirthday: birthday)
            person.id = id
            context.insert(person)
            return person
        }

        let julia = addPerson(juliaID, "Julia Berger", .close, partner: true)
        let anna = addPerson(annaID, "Anna Keller", .close, birthday: birthdayComponents)
        let jonas = addPerson(jonasID, "Jonas Weber", .close)
        let priya = addPerson(priyaID, "Priya Sharma", .regular)
        let tom = addPerson(tomID, "Tom Havel", .orbit)
        let mara = addPerson(maraID, "Mara Lindqvist", .regular)

        context.insert(Interaction(person: julia, date: daysAgo(2), channel: .inPerson, note: "Ramen at Kumo, planned the summer trip"))
        context.insert(Interaction(person: anna, date: daysAgo(37), channel: .inPerson, note: "Coffee — she got the gallery job"))
        context.insert(Interaction(person: anna, date: daysAgo(96), channel: .inPerson, note: "Helped her move the big shelf"))
        context.insert(Interaction(person: jonas, date: daysAgo(22), channel: .call, note: "Long call about the Berlin move"))
        context.insert(Interaction(person: priya, date: daysAgo(80), channel: .message, note: "Congratulated her on the marathon"))
        context.insert(Interaction(person: tom, date: daysAgo(150), channel: .inPerson, note: "Ran into him at Mauerpark"))
        context.insert(Interaction(person: mara, date: daysAgo(48), channel: .message, note: "Sent her the running playlist"))

        context.insert(Commitment(person: jonas, text: "send Jonas the sourdough starter guide"))
        context.insert(Idea(person: anna, text: "Ceramics class voucher for her birthday"))
        context.insert(Idea(person: jonas, text: "Ask how the flat hunt is going"))

        func addEntry(_ text: String, date: Date, mentions: [Person]) {
            let entry = Entry(date: date, text: text, extractionState: .reviewed)
            entry.mentions = mentions
            context.insert(entry)
        }

        addEntry("Ramen with Julia at Kumo. We mapped out the summer trip — she wants the coast, I want the mountains, so it's both.", date: daysAgo(2), mentions: [julia])
        addEntry("Long call with Jonas tonight. The Berlin move is real — he signed the lease. Promised him the sourdough starter guide before he goes.", date: daysAgo(22), mentions: [jonas])
        addEntry("Coffee with Anna. She got the gallery job!! Celebratory pastries. She wants to visit Lisbon in the fall.", date: daysAgo(37), mentions: [anna])
        addEntry("Priya ran her first marathon — 4:12! She sounded so happy on the phone.", date: daysAgo(80), mentions: [priya])

        if variant == "chips" {
            // Pending entry with AI chips near the top of Today — no nudges so it's in frame.
            let pendingDate = calendar.date(bySettingHour: 9, minute: 12, second: 0, of: now) ?? now
            let pending = Entry(date: pendingDate, text: "Lunch with Anna to celebrate the gallery job. Her friend Léo came along — sculptor, very funny. Told Anna I'd send my Lisbon list.")
            pending.id = pendingEntryID
            context.insert(pending)
            services.entrySuggestions[pendingEntryID] = EntrySuggestions(
                entryID: pendingEntryID,
                mentions: [
                    MentionSuggestion(name: "Anna", outcome: .person(annaID), interacted: true, channelGuess: .inPerson, lifeEvent: nil),
                    MentionSuggestion(name: "Léo", outcome: .unknown, interacted: true, channelGuess: .inPerson, lifeEvent: nil),
                ],
                commitments: [
                    CommitmentSuggestion(text: "Lisbon list", personName: "Anna", personOutcome: .person(annaID)),
                ]
            )
        } else {
            // Reason strings mirror NudgeCopy.reasonLine output — same tone rules apply.
            // Staggered timestamps: Today sorts by date desc, so Anna leads.
            context.insert(NudgeLog(personID: annaID, date: now, score: 3.2, reason: String(localized: "It's been a while · birthday in 3 days")))
            context.insert(NudgeLog(personID: jonasID, date: now.addingTimeInterval(-60), score: 2.4, reason: String(localized: "It's been a while · open commitment")))
            context.insert(NudgeLog(personID: priyaID, date: now.addingTimeInterval(-120), score: 1.8, reason: String(localized: "It's been a while")))
        }

        // A fresh run row so evaluateIfStale() doesn't add real nudges on top.
        context.insert(NudgeRun(date: now, selectedCount: 3))
        try? context.save()
    }

    private static func wipe(_ context: ModelContext) {
        // Fetch-and-delete like ExportService — batch delete(model:) skips stores.
        func deleteAll<T: PersistentModel>(_ type: T.Type) {
            for model in (try? context.fetch(FetchDescriptor<T>())) ?? [] {
                context.delete(model)
            }
        }
        deleteAll(NudgeLog.self)
        deleteAll(NudgeRun.self)
        deleteAll(Entry.self)
        deleteAll(Interaction.self)
        deleteAll(Commitment.self)
        deleteAll(Idea.self)
        deleteAll(Person.self)
    }
}

/// Canned extraction so live capture still produces chips on a simulator
/// (Foundation Models are unavailable there).
nonisolated struct DemoExtractionProvider: ExtractionProviding {
    func extract(entryText: String, candidateNames: [String]) async -> ExtractionResult? {
        let people = candidateNames
            .filter { name in
                guard let given = name.split(separator: " ").first else { return false }
                return entryText.localizedCaseInsensitiveContains(given)
            }
            .prefix(3)
            .map { ExtractedPerson(name: String($0), interacted: true, channelGuess: .inPerson, lifeEvent: nil) }
        return ExtractionResult(people: Array(people), commitments: [])
    }
}

/// Canned openers per demo person; all pass DraftSanitizer like real drafts.
nonisolated struct DemoDraftProvider: DraftProviding {
    func draft(for context: DraftContext) async -> String? {
        let raw: String
        switch context.displayName.split(separator: " ").first.map(String.init) {
        case "Anna":
            raw = "Happy almost-birthday! I spotted a print at the flea market that screamed you. When can I hand it over — coffee this week?"
        case "Jonas":
            raw = "How's the packing going? I finally wrote up the sourdough guide I promised — sending it tonight. And I want to see the new flat!"
        case "Priya":
            raw = "Still thinking about your marathon photos. How are the legs — and more importantly, what's the next start line?"
        default:
            raw = "Thought of you today — how are things on your end?"
        }
        return DraftSanitizer.sanitize(raw)
    }
}
#endif
