// NotificationScheduling.swift

import Foundation
import UserNotifications

/// A notification request as a plain value, so the engines can be tested against
/// a recording spy — UN* types are neither Sendable nor constructible in tests.
nonisolated struct NotificationSpec: Sendable, Hashable {
    var identifier: String
    var title: String
    var body: String
    var categoryIdentifier: String?
    var userInfo: [String: String]
    /// nil = deliver immediately (no trigger).
    var fireDateComponents: DateComponents?
}

protocol NotificationScheduling: Sendable {
    func pendingIdentifiers() async -> [String]
    /// Throws when the system refuses the request (e.g. notifications denied) —
    /// an expected state, handled by callers as a no-op.
    func add(_ spec: NotificationSpec) async throws
    func removePending(identifiers: [String]) async
    func removeDelivered(identifiers: [String]) async
}

/// The production scheduler — the only place engine code touches UN* types.
nonisolated final class SystemNotificationScheduler: NotificationScheduling {
    func pendingIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
    }

    func add(_ spec: NotificationSpec) async throws {
        let content = UNMutableNotificationContent()
        content.title = spec.title
        content.body = spec.body
        content.sound = .default
        if let category = spec.categoryIdentifier {
            content.categoryIdentifier = category
        }
        content.userInfo = spec.userInfo
        // Components carry their calendar's time zone so triggers built from an
        // injected calendar fire at that calendar's wall-clock time, not the device's.
        let trigger = spec.fireDateComponents.map {
            UNCalendarNotificationTrigger(dateMatching: $0, repeats: false)
        }
        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: spec.identifier, content: content, trigger: trigger)
        )
    }

    func removePending(identifiers: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDelivered(identifiers: [String]) async {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}
