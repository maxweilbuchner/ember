// EmberApp.swift

import BackgroundTasks
import SwiftData
import SwiftUI
import UserNotifications

@main
struct EmberApp: App {
    private let container: ModelContainer
    @State private var services: AppServices
    private let notificationDelegate: NotificationDelegate

    init() {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        do {
            container = try ModelContainer(
                for: schema,
                migrationPlan: EmberMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            fatalError("Failed to create model container: \(error)")
        }

        let services = AppServices(container: container)
        _services = State(initialValue: services)

        // Delegate assignment, category registration, and BGTask registration must
        // all happen before the app finishes launching — hence here in App.init.
        let delegate = NotificationDelegate(engine: services.nudgeEngine, router: services.router)
        notificationDelegate = delegate
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.setNotificationCategories([NudgeEngine.notificationCategory()])

        Self.registerBackgroundTasks(nudgeEngine: services.nudgeEngine, birthdayEngine: services.birthdayEngine)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
        .environment(services)
    }

    private static func registerBackgroundTasks(nudgeEngine: NudgeEngine, birthdayEngine: BirthdayEngine) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: NudgeEngine.taskIdentifier, using: nil) { task in
            nonisolated(unsafe) let task = task
            let work = Task {
                await nudgeEngine.evaluate()
                await birthdayEngine.refresh()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }
}
