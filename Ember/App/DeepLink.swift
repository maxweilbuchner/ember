// DeepLink.swift

import Foundation

/// ember://capture — open with the capture field focused (lock-screen widget, M5).
/// ember://compose/<personUUID> — nudge notification tap → compose for that person.
nonisolated enum DeepLink: Equatable, Sendable {
    case capture
    case compose(UUID)

    init?(url: URL) {
        guard url.scheme?.lowercased() == "ember" else { return nil }
        switch url.host()?.lowercased() {
        case "capture":
            self = .capture
        case "compose":
            guard let personID = url.pathComponents.dropFirst().first.flatMap(UUID.init) else { return nil }
            self = .compose(personID)
        default:
            return nil
        }
    }
}
