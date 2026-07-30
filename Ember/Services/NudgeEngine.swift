// NudgeEngine.swift

import BackgroundTasks
import Foundation
import SwiftData
import UserNotifications

/// The heart of the app. Runs weekly (BGAppRefreshTask, best-effort) and on app
/// foreground when stale, scores every non-paused non-partner Person, and delivers
/// at most 3 nudge notifications with context. All scheduling state lives in
/// SwiftData (NudgeLog/NudgeRun) — never UserDefaults (spec §4.4/§8).
actor NudgeEngine {
    static let taskIdentifier = "com.maw.ember.nudge.refresh"
    static let categoryIdentifier = "NUDGE"
    static let spokeActionID = "NUDGE_SPOKE"
    static let snoozeActionID = "NUDGE_SNOOZE"

    private let container: ModelContainer
    private let contacts: any ContactResolving
    private let scheduler: any NotificationScheduling
    private var draftProvider: (any DraftProviding)?

    init(
        container: ModelContainer,
        contacts: any ContactResolving,
        scheduler: any NotificationScheduling = SystemNotificationScheduler()
    ) {
        self.container = container
        self.contacts = contacts
        self.scheduler = scheduler
    }

    func setDraftProvider(_ provider: any DraftProviding) {
        draftProvider = provider
    }

    nonisolated static func notificationCategory() -> UNNotificationCategory {
        let spoke = UNNotificationAction(
            identifier: spokeActionID,
            title: String(localized: "We spoke"),
            options: [] // no .foreground — logs the interaction without opening the app
        )
        let snooze = UNNotificationAction(
            identifier: snoozeActionID,
            title: String(localized: "Snooze 2 weeks"),
            options: []
        )
        return UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [spoke, snooze],
            intentIdentifiers: [],
            options: []
        )
    }

    // MARK: Evaluation

    /// BGTask is best-effort, so the app also re-evaluates on foreground
    /// if more than 7 days have passed since the last run.
    func evaluateIfStale(now: Date = .now) async {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<NudgeRun>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        if let lastRun = (try? context.fetch(descriptor))?.first?.date,
           now.timeIntervalSince(lastRun) < 7 * 86_400 {
            return
        }
        await evaluate(now: now)
    }

    func evaluate(now: Date = .now) async {
        let context = ModelContext(container)
        let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        let logs = (try? context.fetch(FetchDescriptor<NudgeLog>())) ?? []

        // Nudges nobody acted on within a week are quietly expired — no guilt, no re-surfacing.
        for log in logs where log.outcome == .pending && now.timeIntervalSince(log.date) > 7 * 86_400 {
            log.outcome = .expired
        }

        var latestEventByPerson: [UUID: Date] = [:]
        for log in logs {
            latestEventByPerson[log.personID] = max(latestEventByPerson[log.personID] ?? .distantPast, log.date)
        }

        var inputs: [ScoringInput] = []
        for person in people {
            guard person.tier != .paused, !person.isPartnerMode else { continue }
            var contactBirthday: DateComponents?
            if let contactID = person.contactID {
                contactBirthday = await contacts.resolve(contactID)?.birthday
            }
            let birthday = BirthdayResolution.effectiveBirthday(contact: contactBirthday, manual: person.manualBirthday)
            var nearestCustomDate: (label: String, daysAway: Int)?
            for customDate in person.customDates {
                guard let daysAway = BirthdayMath.daysUntilNextBirthday(
                    DateComponents(month: customDate.month, day: customDate.day),
                    from: now
                ) else { continue }
                if daysAway < (nearestCustomDate?.daysAway ?? .max) {
                    nearestCustomDate = (customDate.label, daysAway)
                }
            }
            let lastInteraction = person.interactions.max { $0.date < $1.date }
            let openCommitments = person.commitments.filter { !$0.isDone }
            inputs.append(ScoringInput(
                personID: person.id,
                displayName: person.displayNameCache,
                tier: person.tier,
                isPartner: person.isPartnerMode,
                daysSinceLastInteraction: lastInteraction.map { now.timeIntervalSince($0.date) / 86_400 },
                daysSinceCreated: now.timeIntervalSince(person.createdAt) / 86_400,
                daysUntilBirthday: birthday.flatMap { BirthdayMath.daysUntilNextBirthday($0, from: now) },
                daysUntilCustomDate: nearestCustomDate?.daysAway,
                customDateLabel: nearestCustomDate?.label,
                openCommitmentCount: openCommitments.count,
                daysSinceLastNudgeEvent: latestEventByPerson[person.id].map { now.timeIntervalSince($0) / 86_400 },
                lastInteractionNote: lastInteraction?.note,
                lastInteractionChannel: lastInteraction?.channel,
                openCommitmentTexts: openCommitments.prefix(3).map(\.text)
            ))
        }

        let selected = NudgeScoring.select(inputs)
        for candidate in selected {
            let notificationID = "nudge-\(candidate.input.personID.uuidString)-\(Int(now.timeIntervalSince1970))"
            let log = NudgeLog(
                personID: candidate.input.personID,
                date: now,
                score: candidate.score,
                reason: NudgeCopy.reasonLine(for: candidate),
                outcome: .pending,
                notificationID: notificationID
            )
            context.insert(log)
            await scheduleNotification(for: candidate, notificationID: notificationID, logID: log.id)
        }

        context.insert(NudgeRun(date: now, selectedCount: selected.count))
        try? context.save()
        scheduleNextBackgroundRefresh(after: now)
    }

    // MARK: Notification action handlers (invoked without opening the app)

    func handleWeSpoke(personID: UUID, nudgeLogID: UUID?, now: Date = .now) async {
        let context = ModelContext(container)
        guard let person = fetchPerson(personID, in: context) else { return }
        context.insert(Interaction(person: person, date: now, channel: .other))
        await closeLog(nudgeLogID, personID: personID, outcome: .actedOn, in: context)
        try? context.save()
    }

    func handleSnooze(personID: UUID, nudgeLogID: UUID?, now: Date = .now) async {
        let context = ModelContext(container)
        await closeLog(nudgeLogID, personID: personID, outcome: .snoozed, in: context)
        // A fresh log entry gives the full 14-day quiet window from the snooze itself.
        context.insert(NudgeLog(
            personID: personID,
            date: now,
            score: 0,
            reason: String(localized: "Snoozed"),
            outcome: .snoozed
        ))
        try? context.save()
    }

    /// A Person was deleted or merged away: close their pending nudges and pull
    /// the notifications — actions on a dead person's nudge would otherwise
    /// silently no-op (or, for snooze, insert an orphan log).
    func personRemoved(_ personID: UUID) async {
        let context = ModelContext(container)
        let logs = (try? context.fetch(FetchDescriptor<NudgeLog>())) ?? []
        for log in logs where log.personID == personID && log.outcome == .pending {
            log.outcome = .expired
            if let notificationID = log.notificationID {
                await scheduler.removeDelivered(identifiers: [notificationID])
                await scheduler.removePending(identifiers: [notificationID])
            }
        }
        try? context.save()
    }

    // MARK: Private

    private func fetchPerson(_ personID: UUID, in context: ModelContext) -> Person? {
        let descriptor = FetchDescriptor<Person>(predicate: #Predicate { $0.id == personID })
        return (try? context.fetch(descriptor))?.first
    }

    private func closeLog(_ nudgeLogID: UUID?, personID: UUID, outcome: NudgeOutcome, in context: ModelContext) async {
        let logs = (try? context.fetch(FetchDescriptor<NudgeLog>())) ?? []
        let target = logs.first { $0.id == nudgeLogID }
            ?? logs.filter { $0.personID == personID && $0.outcome == .pending }
                .max { $0.date < $1.date }
        guard let target else { return }
        target.outcome = outcome
        if let notificationID = target.notificationID {
            await scheduler.removeDelivered(identifiers: [notificationID])
            await scheduler.removePending(identifiers: [notificationID])
        }
    }

    private func scheduleNotification(for candidate: NudgeCandidate, notificationID: String, logID: UUID) async {
        let draft = await draftProvider?.draft(for: DraftContext(from: candidate.input))
        let spec = NotificationSpec(
            identifier: notificationID,
            title: NudgeCopy.notificationTitle(for: candidate),
            body: NudgeCopy.notificationBody(for: candidate, draft: draft),
            categoryIdentifier: Self.categoryIdentifier,
            userInfo: [
                "personID": candidate.input.personID.uuidString,
                "nudgeLogID": logID.uuidString,
            ],
            fireDateComponents: nil
        )
        try? await scheduler.add(spec)
    }

    private func scheduleNextBackgroundRefresh(after date: Date) {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = date.addingTimeInterval(7 * 86_400)
        // Unsupported on simulator; harmless there.
        try? BGTaskScheduler.shared.submit(request)
    }
}
