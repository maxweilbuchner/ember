// DeepLink.swift

import Foundation

/// ember://capture — open with the capture field focused (lock-screen widget, M5).
/// ember://compose/<personUUID> — nudge notification tap → compose for that person.
nonisolated enum DeepLink: Equatable, Sendable {
    case capture
    case compose(UUID)
    #if DEBUG
    // Screenshot-script navigation (Scripts/screenshots.sh):
    // ember://tab/<today|people|journal>, ember://person/<uuid>, ember://settings
    case tab(AppTab)
    case person(UUID)
    case settings
    #endif

    init?(url: URL) {
        guard url.scheme?.lowercased() == "ember" else { return nil }
        switch url.host()?.lowercased() {
        case "capture":
            self = .capture
        case "compose":
            guard let personID = url.pathComponents.dropFirst().first.flatMap(UUID.init) else { return nil }
            self = .compose(personID)
        #if DEBUG
        case "tab":
            switch url.pathComponents.dropFirst().first?.lowercased() {
            case "today": self = .tab(.today)
            case "people": self = .tab(.people)
            case "journal": self = .tab(.journal)
            default: return nil
            }
        case "person":
            guard let personID = url.pathComponents.dropFirst().first.flatMap(UUID.init) else { return nil }
            self = .person(personID)
        case "settings":
            self = .settings
        #endif
        default:
            return nil
        }
    }
}
