// NotificationDelegate.swift

import Foundation
import UserNotifications

/// Routes NUDGE notification actions to the engine — "We spoke" and "Snooze" run
/// entirely in the background without opening the app; the default tap deep-links
/// into the compose flow.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let engine: NudgeEngine
    private let router: AppRouter

    init(engine: NudgeEngine, router: AppRouter) {
        self.engine = engine
        self.router = router
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
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
