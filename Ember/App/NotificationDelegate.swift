// NotificationDelegate.swift

import Foundation
import SwiftData
import UserNotifications

/// Routes NUDGE notification actions to the engine — "We spoke" and "Snooze" run
/// entirely in the background without opening the app; the default tap deep-links
/// into the compose flow.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let engine: NudgeEngine
    private let router: AppRouter
    private let container: ModelContainer

    init(engine: NudgeEngine, router: AppRouter, container: ModelContainer) {
        self.engine = engine
        self.router = router
        self.container = container
    }

    /// Last-mile check against a request that outran its cancellation — a trigger
    /// firing in the same moment the switch was flipped. This only governs
    /// foreground banners; pulling the requests remains the real guarantee.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let banner: UNNotificationPresentationOptions = [.banner, .sound, .list]
        let flags = NotificationSettings.flags(in: ModelContext(container))
        let request = notification.request
        if request.content.categoryIdentifier == NudgeEngine.categoryIdentifier {
            return flags.nudgesEnabled ? banner : []
        }
        if DateEngine.identifierPrefixes.contains(where: { request.identifier.hasPrefix($0) }) {
            return flags.occasionAlertsEnabled ? banner : []
        }
        return banner
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let personID = (userInfo["personID"] as? String).flatMap(UUID.init) else { return }
        let nudgeLogID = (userInfo["nudgeLogID"] as? String).flatMap(UUID.init)
        let action = response.actionIdentifier

        switch action {
        case NudgeEngine.spokeActionID:
            await engine.handleWeSpoke(personID: personID, nudgeLogID: nudgeLogID)
        case NudgeEngine.snoozeActionID:
            // Actioning a banner that outlived the nudge switch is harmless: the
            // fresh log is `.snoozed`, so it never surfaces on Today and only
            // widens the quiet window.
            await engine.handleSnooze(personID: personID, nudgeLogID: nudgeLogID)
        case UNNotificationDefaultActionIdentifier:
            let router = router
            await MainActor.run {
                router.handle(.compose(personID))
            }
        default:
            break
        }
    }
}
