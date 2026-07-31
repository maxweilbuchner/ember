// ExportService.swift

import Foundation
import SwiftData
import UserNotifications

/// Full data export (JSON + images → zip) and the destructive delete-everything.
/// Both exist for trust: the data is the user's, provably and completely.

// MARK: Export document (versioned, decoupled from the SwiftData schema)

nonisolated struct EmberExport: Codable, Sendable {
    /// 2: adds `people[].relation` and `customDates`.
    var version: Int = 2
    var exportedAt: Date
    var people: [PersonExport] = []
    var entries: [EntryExport] = []
    var interactions: [InteractionExport] = []
    var commitments: [CommitmentExport] = []
    var ideas: [IdeaExport] = []
    var customDates: [CustomDateExport] = []
    var nudgeLogs: [NudgeLogExport] = []
}

nonisolated struct PersonExport: Codable, Sendable {
    var id: UUID
    var contactID: String?
    var displayName: String
    var tier: Int
    var isPartner: Bool
    var birthdayMonth: Int?
    var birthdayDay: Int?
    var birthdayYear: Int?
    var relation: String?
    var createdAt: Date
}

nonisolated struct EntryExport: Codable, Sendable {
    var id: UUID
    var date: Date
    var text: String
    var imageFilenames: [String]
    var extractionState: Int
    var mentionPersonIDs: [UUID]
}

nonisolated struct InteractionExport: Codable, Sendable {
    var id: UUID
    var personID: UUID?
    var date: Date
    var dateIsApproximate: Bool
    var channel: Int
    var note: String?
    var sourceEntryID: UUID?
}

nonisolated struct CommitmentExport: Codable, Sendable {
    var id: UUID
    var personID: UUID?
    var text: String
    var dueHint: Date?
    var isDone: Bool
    var createdAt: Date
    var sourceEntryID: UUID?
}

nonisolated struct IdeaExport: Codable, Sendable {
    var id: UUID
    var personID: UUID?
    var text: String
    var isDone: Bool
    var createdAt: Date
}

nonisolated struct CustomDateExport: Codable, Sendable {
    var id: UUID
    var personID: UUID?
    var label: String
    var month: Int
    var day: Int
    var year: Int?
    var createdAt: Date
}

nonisolated struct NudgeLogExport: Codable, Sendable {
    var id: UUID
    var personID: UUID
    var date: Date
    var score: Double
    var reason: String
    var outcome: Int
}

// MARK: Service

actor ExportService {
    private let container: ModelContainer
    private let images = ImageStore()

    init(container: ModelContainer) {
        self.container = container
    }

    func buildExport(now: Date = .now) -> EmberExport {
        let context = ModelContext(container)
        var export = EmberExport(exportedAt: now)

        for person in (try? context.fetch(FetchDescriptor<Person>())) ?? [] {
            export.people.append(PersonExport(
                id: person.id,
                contactID: person.contactID,
                displayName: person.displayNameCache,
                tier: person.tier.rawValue,
                isPartner: person.isPartnerMode,
                birthdayMonth: person.manualBirthdayMonth,
                birthdayDay: person.manualBirthdayDay,
                birthdayYear: person.manualBirthdayYear,
                relation: person.manualRelationRaw,
                createdAt: person.createdAt
            ))
        }
        for entry in (try? context.fetch(FetchDescriptor<Entry>())) ?? [] {
            export.entries.append(EntryExport(
                id: entry.id,
                date: entry.date,
                text: entry.text,
                imageFilenames: entry.imageFilenames,
                extractionState: entry.extractionState.rawValue,
                mentionPersonIDs: entry.mentions.map(\.id)
            ))
        }
        for interaction in (try? context.fetch(FetchDescriptor<Interaction>())) ?? [] {
            export.interactions.append(InteractionExport(
                id: interaction.id,
                personID: interaction.person?.id,
                date: interaction.date,
                dateIsApproximate: interaction.dateIsApproximate,
                channel: interaction.channel.rawValue,
                note: interaction.note,
                sourceEntryID: interaction.sourceEntryID
            ))
        }
        for commitment in (try? context.fetch(FetchDescriptor<Commitment>())) ?? [] {
            export.commitments.append(CommitmentExport(
                id: commitment.id,
                personID: commitment.person?.id,
                text: commitment.text,
                dueHint: commitment.dueHint,
                isDone: commitment.isDone,
                createdAt: commitment.createdAt,
                sourceEntryID: commitment.sourceEntryID
            ))
        }
        for idea in (try? context.fetch(FetchDescriptor<Idea>())) ?? [] {
            export.ideas.append(IdeaExport(
                id: idea.id,
                personID: idea.person?.id,
                text: idea.text,
                isDone: idea.isDone,
                createdAt: idea.createdAt
            ))
        }
        for customDate in (try? context.fetch(FetchDescriptor<CustomDate>())) ?? [] {
            export.customDates.append(CustomDateExport(
                id: customDate.id,
                personID: customDate.person?.id,
                label: customDate.label,
                month: customDate.month,
                day: customDate.day,
                year: customDate.year,
                createdAt: customDate.createdAt
            ))
        }
        for log in (try? context.fetch(FetchDescriptor<NudgeLog>())) ?? [] {
            export.nudgeLogs.append(NudgeLogExport(
                id: log.id,
                personID: log.personID,
                date: log.date,
                score: log.score,
                reason: log.reason,
                outcome: log.outcome.rawValue
            ))
        }
        return export
    }

    /// Writes "Ember Export/ember.json" + Images/, zips it, returns the zip URL.
    func exportZip(now: Date = .now) throws -> URL {
        let export = buildExport(now: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = try encoder.encode(export)

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmberExport-\(UUID().uuidString)", isDirectory: true)
        let root = staging.appendingPathComponent("Ember Export", isDirectory: true)
        let imagesDirectory = root.appendingPathComponent("Images", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try json.write(to: root.appendingPathComponent("ember.json"))

        let imageFiles = (try? FileManager.default.contentsOfDirectory(at: ImageStore.directory, includingPropertiesForKeys: nil)) ?? []
        for file in imageFiles {
            try? FileManager.default.copyItem(at: file, to: imagesDirectory.appendingPathComponent(file.lastPathComponent))
        }

        let zipURL = try Self.zip(folder: root)
        try? FileManager.default.removeItem(at: staging)
        return zipURL
    }

    /// The only zero-dependency zip on Apple platforms: NSFileCoordinator's
    /// `.forUploading` produces a zip of a folder in its accessor.
    private nonisolated static func zip(folder: URL) throws -> URL {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        nonisolated(unsafe) var copyError: Error?
        nonisolated(unsafe) var result: URL?

        coordinator.coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zippedURL in
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("Ember Export \(UUID().uuidString.prefix(8)).zip")
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: zippedURL, to: destination)
                result = destination
            } catch {
                copyError = error
            }
        }

        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        guard let result else {
            throw CocoaError(.fileWriteUnknown)
        }
        return result
    }

    /// Deletes every entity, every image, and every scheduled notification.
    /// The caller is responsible for the typed confirmation UI.
    func deleteEverything() {
        let context = ModelContext(container)
        // Explicit fetch-and-delete: SwiftData's batch delete(model:) skips
        // in-memory stores (breaking tests) and bypasses cascade bookkeeping.
        func wipe<T: PersistentModel>(_ type: T.Type) {
            for object in (try? context.fetch(FetchDescriptor<T>())) ?? [] {
                context.delete(object)
            }
        }
        wipe(Interaction.self)
        wipe(Commitment.self)
        wipe(Idea.self)
        wipe(CustomDate.self)
        wipe(Entry.self)
        wipe(Person.self)
        wipe(NudgeLog.self)
        wipe(NudgeRun.self)
        wipe(DateAlertRecord.self)
        // Deliberately wiped but never exported: the notification switches are a
        // device preference like the app lock, not user data. Clearing them here
        // is what stops a re-onboarded app from staying silently paused.
        wipe(NotificationSettings.self)
        try? context.save()

        try? FileManager.default.removeItem(at: ImageStore.directory)

        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}
