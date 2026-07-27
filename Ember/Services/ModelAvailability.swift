// ModelAvailability.swift

import Foundation
import FoundationModels

/// The app's view of Foundation Models availability. Extraction and drafts are
/// enhancements — every unavailable state maps to a working manual path.
nonisolated enum ModelAvailability: Equatable, Sendable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady

    static var current: ModelAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .deviceNotEligible
            case .appleIntelligenceNotEnabled:
                return .appleIntelligenceNotEnabled
            case .modelNotReady:
                return .modelNotReady
            @unknown default:
                return .deviceNotEligible
            }
        }
    }

    var statusText: String {
        switch self {
        case .available: String(localized: "On")
        case .deviceNotEligible: String(localized: "Not supported on this device")
        case .appleIntelligenceNotEnabled: String(localized: "Apple Intelligence is off")
        case .modelNotReady: String(localized: "Downloading…")
        }
    }

    var explanation: String? {
        switch self {
        case .available:
            nil
        case .deviceNotEligible:
            String(localized: "Ember works fully without it — you'll review mentions by hand instead of getting suggestions.")
        case .appleIntelligenceNotEnabled:
            String(localized: "Turn on Apple Intelligence in Settings to get automatic suggestions and drafted openers.")
        case .modelNotReady:
            String(localized: "Suggestions will switch on automatically once the on-device model finishes downloading.")
        }
    }
}
