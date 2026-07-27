// BirthdayEngine.swift

import Foundation
import SwiftData
import UserNotifications

nonisolated struct BirthdayItem: Sendable, Hashable, Identifiable {
    var personID: UUID
    var displayName: String
    var daysAway: Int

    var id: UUID { personID }
}

/// Birthday notifications are separate from nudges: only `.close`/`.regular` tiers
/// and the partner, on the day (9:00) plus a 3-day heads-up. Scheduled with
/// deterministic identifiers so refreshing replaces rather than duplicates.
actor BirthdayEngine {
    static let identifierPrefix = "birthday-"

    private let container: ModelContainer
    private let contacts: ContactService

    init(container: ModelContainer, contacts: ContactService) {
        self.container = container
        self.contacts = contacts
    }

    func refresh(now: Date = .now) async {
        let items = await upcoming(withinDays: 7, now: now)
        let center = UNUserNotificationCenter.current()

        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        for item in items {
            guard let birthdayDate = calendar.date(byAdding: .day, value: item.daysAway, to: startOfToday) else { continue }
            let dayStamp = birthdayDate.formatted(.iso8601.year().month().day())

            schedule(
                identifier: "\(Self.identifierPrefix)\(item.personID.uuidString)-\(dayStamp)-day",
                fireDate: at(hour: 9, of: birthdayDate, calendar: calendar),
                title: String(localized: "\(item.displayName)'s birthday is today 🎂"),
                body: String(localized: "A lovely day to reach out."),
                personID: item.personID,
                now: now,
                center: center
            )

            if item.daysAway >= 3, let headsUpDate = calendar.date(byAdding: .day, value: -3, to: birthdayDate) {
                schedule(
                    identifier: "\(Self.identifierPrefix)\(item.personID.uuidString)-\(dayStamp)-headsup",
                    fireDate: at(hour: 9, of: headsUpDate, calendar: calendar),
                    title: String(localized: "\(item.displayName)'s birthday is in 3 days"),
                    body: String(localized: "Time enough to plan something small."),
                    personID: item.personID,
                    now: now,
                    center: center
                )
            }
        }
    }

    /// Also feeds the Today tab's "upcoming birthdays" section.
    func upcoming(withinDays window: Int, now: Date = .now) async -> [BirthdayItem] {
        let context = ModelContext(container)
        let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        var items: [BirthdayItem] = []
        for person in people {
            let eligible = person.isPartnerMode || person.tier == .close || person.tier == .regular
            guard eligible else { continue }
            let birthday: DateComponents?
            if let manual = person.manualBirthday {
                birthday = manual
            } else if let contactID = person.contactID {
                birthday = await contacts.resolve(contactID)?.birthday
            } else {
                birthday = nil
            }
            guard let birthday,
                  let daysAway = BirthdayMath.daysUntilNextBirthday(birthday, from: now),
                  daysAway <= window else { continue }
            items.append(BirthdayItem(personID: person.id, displayName: person.displayNameCache, daysAway: daysAway))
        }
        return items.sorted { $0.daysAway < $1.daysAway }
    }

    private func at(hour: Int, of date: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
    }

    private func schedule(
        identifier: String,
        fireDate: Date,
        title: String,
        body: String,
        personID: UUID,
        now: Date,
        center: UNUserNotificationCenter
    ) {
        guard fireDate > now else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["personID": personID.uuidString]
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }
}
