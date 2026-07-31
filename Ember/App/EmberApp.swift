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
        let schema = Schema(versionedSchema: CurrentSchema.self)
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

        #if DEBUG
        if DemoSeed.isActive {
            DemoSeed.apply(container: container, services: services)
        }
        #endif

        // Delegate assignment, category registration, and BGTask registration must
        // all happen before the app finishes launching — hence here in App.init.
        let delegate = NotificationDelegate(
            engine: services.nudgeEngine,
            router: services.router,
            container: container
        )
        notificationDelegate = delegate
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.setNotificationCategories([NudgeEngine.notificationCategory()])

        Self.registerBackgroundTasks(nudgeEngine: services.nudgeEngine, dateEngine: services.dateEngine)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
        .environment(services)
    }

    private static func registerBackgroundTasks(nudgeEngine: NudgeEngine, dateEngine: DateEngine) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: NudgeEngine.taskIdentifier, using: nil) { task in
            nonisolated(unsafe) let task = task
            let work = Task {
                await nudgeEngine.evaluate()
                await dateEngine.refresh()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }
}
