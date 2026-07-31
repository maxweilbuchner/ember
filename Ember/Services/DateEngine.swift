// DateEngine.swift

import Foundation
import SwiftData

/// One upcoming occasion — a birthday or a custom date — feeding both the Today
/// tab and notification scheduling.
nonisolated struct UpcomingOccasion: Sendable, Hashable, Identifiable {
    nonisolated enum Kind: Sendable, Hashable {
        case birthday
        case custom(label: String)
    }

    /// Stable identifier base: "birthday-<personID>" / "date-<customDateID>".
    /// Notification identifiers append "-<dayStamp>-day|-headsup".
    var id: String
    var personID: UUID
    var displayName: String
    var kind: Kind
    var daysAway: Int
}

/// Occasion notifications (birthdays + custom dates) are separate from nudges:
/// only `.close`/`.regular` tiers and the partner, on the day (9:00) plus a
/// 3-day heads-up. Scheduled with deterministic identifiers so refreshing
/// replaces rather than duplicates. A day-of moment already past 9:00 is
/// delivered immediately, once — deduplicated through `DateAlertRecord`
/// (scheduling state lives in SwiftData).
actor DateEngine {
    static let identifierPrefixes = ["birthday-", "date-"]

    private let container: ModelContainer
    private let contacts: any ContactResolving
    private let scheduler: any NotificationScheduling
    private let calendar: Calendar

    init(
        container: ModelContainer,
        contacts: any ContactResolving,
        scheduler: any NotificationScheduling = SystemNotificationScheduler(),
        calendar: Calendar = .current
    ) {
        self.container = container
        self.contacts = contacts
        self.scheduler = scheduler
        self.calendar = calendar
    }

    func refresh(now: Date = .now) async {
        // Runs in both states: the cancel path when alerts are off, the
        // anti-duplication sweep when they're on.
        await cancelScheduledOccasions()
        // Occasion alerts switched off in Settings. `upcoming` stays ungated
        // below, so Today's read-only "Coming up" list is untouched — turning
        // off alerts must not hide information (GH #10).
        guard NotificationSettings.flags(in: ModelContext(container)).occasionAlertsEnabled else { return }

        let occasions = await upcoming(withinDays: 7, now: now)
        let startOfToday = calendar.startOfDay(for: now)
        // iOS caps pending requests at 64 per app. Occasions arrive soonest-first
        // and produce ≤2 requests each, so trimming the tail keeps the nearest.
        for occasion in occasions.prefix(30) {
            guard let occasionDate = calendar.date(byAdding: .day, value: occasion.daysAway, to: startOfToday) else { continue }
            let dayStamp = dayStamp(for: occasionDate)

            await schedule(
                identifier: "\(occasion.id)-\(dayStamp)-day",
                fireDate: at(hour: 9, of: occasionDate),
                title: dayOfTitle(for: occasion),
                body: NudgeCopy.birthdayDayOfBody(), // shared occasion body
                personID: occasion.personID,
                now: now,
                catchesUpSameDay: true
            )

            if occasion.daysAway >= 3, let headsUpDate = calendar.date(byAdding: .day, value: -3, to: occasionDate) {
                await schedule(
                    identifier: "\(occasion.id)-\(dayStamp)-headsup",
                    fireDate: at(hour: 9, of: headsUpDate),
                    title: headsUpTitle(for: occasion),
                    body: NudgeCopy.birthdayHeadsUpBody(), // shared occasion body
                    personID: occasion.personID,
                    now: now,
                    catchesUpSameDay: false // a late "in 3 days" would be wrong
                )
            }
        }
    }

    /// Pulls every birthday/date notification, scheduled or already delivered.
    /// The prefix filter is what keeps the two Settings switches independent:
    /// this can never touch a `nudge-` identifier, and `cancelScheduledNudges`
    /// removes by explicit `NudgeLog.notificationID`, so it can never touch one
    /// of these.
    func cancelScheduledOccasions() async {
        func ours(_ identifiers: [String]) -> [String] {
            identifiers.filter { identifier in
                Self.identifierPrefixes.contains { identifier.hasPrefix($0) }
            }
        }
        let stalePending = ours(await scheduler.pendingIdentifiers())
        if !stalePending.isEmpty {
            await scheduler.removePending(identifiers: stalePending)
        }
        let staleDelivered = ours(await scheduler.deliveredIdentifiers())
        if !staleDelivered.isEmpty {
            await scheduler.removeDelivered(identifiers: staleDelivered)
        }
    }

    /// Also feeds the Today tab's "coming up" section. Sorted soonest-first,
    /// then by name for determinism.
    func upcoming(withinDays window: Int, now: Date = .now) async -> [UpcomingOccasion] {
        let context = ModelContext(container)
        let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        var occasions: [UpcomingOccasion] = []
        for person in people {
            let eligible = person.isPartnerMode || person.tier == .close || person.tier == .regular
            guard eligible else { continue }

            var contactBirthday: DateComponents?
            if let contactID = person.contactID {
                contactBirthday = await contacts.resolve(contactID)?.birthday
            }
            let birthday = BirthdayResolution.effectiveBirthday(contact: contactBirthday, manual: person.manualBirthday)
            if let birthday,
               let daysAway = BirthdayMath.daysUntilNextBirthday(birthday, from: now, calendar: calendar),
               daysAway <= window {
                occasions.append(UpcomingOccasion(
                    id: "birthday-\(person.id.uuidString)",
                    personID: person.id,
                    displayName: person.displayNameCache,
                    kind: .birthday,
                    daysAway: daysAway
                ))
            }

            for customDate in person.customDates {
                guard let daysAway = BirthdayMath.daysUntilNextBirthday(
                    DateComponents(month: customDate.month, day: customDate.day),
                    from: now,
                    calendar: calendar
                ), daysAway <= window else { continue }
                occasions.append(UpcomingOccasion(
                    id: "date-\(customDate.id.uuidString)",
                    personID: person.id,
                    displayName: person.displayNameCache,
                    kind: .custom(label: customDate.label),
                    daysAway: daysAway
                ))
            }
        }
        return occasions.sorted {
            if $0.daysAway != $1.daysAway { return $0.daysAway < $1.daysAway }
            return $0.displayName < $1.displayName
        }
    }

    // MARK: Private

    private func dayOfTitle(for occasion: UpcomingOccasion) -> String {
        switch occasion.kind {
        case .birthday:
            NudgeCopy.birthdayDayOfTitle(name: occasion.displayName)
        case .custom(let label):
            NudgeCopy.customDateDayOfTitle(name: occasion.displayName, label: label)
        }
    }

    private func headsUpTitle(for occasion: UpcomingOccasion) -> String {
        switch occasion.kind {
        case .birthday:
            NudgeCopy.birthdayHeadsUpTitle(name: occasion.displayName)
        case .custom(let label):
            NudgeCopy.customDateHeadsUpTitle(name: occasion.displayName, label: label)
        }
    }

    /// Local calendar day, not ISO-8601 (which formats in UTC and names the wrong
    /// day east of Greenwich).
    private func dayStamp(for date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private func at(hour: Int, of date: Date) -> Date {
        // A DST gap can swallow the hour; try the next one before falling back to
        // an absolute offset from midnight (never plain `date` — that's midnight
        // and would be dropped as already-passed).
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date)
            ?? calendar.date(bySettingHour: hour + 1, minute: 0, second: 0, of: date)
            ?? calendar.startOfDay(for: date).addingTimeInterval(TimeInterval(hour) * 3600)
    }

    private func schedule(
        identifier: String,
        fireDate: Date,
        title: String,
        body: String,
        personID: UUID,
        now: Date,
        catchesUpSameDay: Bool
    ) async {
        var spec = NotificationSpec(
            identifier: identifier,
            title: title,
            body: body,
            categoryIdentifier: nil,
            userInfo: ["personID": personID.uuidString],
            fireDateComponents: nil
        )
        if fireDate > now {
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            components.timeZone = calendar.timeZone
            spec.fireDateComponents = components
        } else if catchesUpSameDay, calendar.isDate(fireDate, inSameDayAs: now) {
            // Past 9:00 on the day itself (e.g. first foreground at 10am):
            // deliver immediately, exactly once.
            guard markAlertSent(identifier: identifier, now: now) else { return }
        } else {
            return // the moment has passed
        }
        // Throws when notifications are denied — an expected, silent state.
        try? await scheduler.add(spec)
    }

    /// True the first time an identifier is recorded; false when it was already
    /// delivered. Prunes records older than 60 days while it's here.
    private func markAlertSent(identifier: String, now: Date) -> Bool {
        let context = ModelContext(container)
        let records = (try? context.fetch(FetchDescriptor<DateAlertRecord>())) ?? []
        guard !records.contains(where: { $0.identifier == identifier }) else { return false }
        for record in records where now.timeIntervalSince(record.sentAt) > 60 * 86_400 {
            context.delete(record)
        }
        context.insert(DateAlertRecord(identifier: identifier, sentAt: now))
        try? context.save()
        return true
    }
}
