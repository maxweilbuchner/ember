// ImageStore.swift

import Foundation

/// Entry images live as files under Application Support/Images; the store keeps
/// filenames only, resolved at runtime (absolute paths break when the app
/// container UUID changes across reinstalls — spec §8).
nonisolated struct ImageStore: Sendable {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func url(for filename: String) -> URL {
        Self.directory.appendingPathComponent(filename)
    }

    func save(_ data: Data, fileExtension: String = "jpg") throws -> String {
        let filename = UUID().uuidString + "." + fileExtension
        try data.write(to: url(for: filename), options: .atomic)
        return filename
    }

    func delete(_ filename: String) {
        try? FileManager.default.removeItem(at: url(for: filename))
    }
}
