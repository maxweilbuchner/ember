// SecurityService.swift

import Foundation
import LocalAuthentication

/// FaceID/passcode app lock. The enabled flag lives in UserDefaults (a UI
/// preference — the engine never reads it, so the SwiftData-only rule for
/// engine state doesn't apply). The authenticator is injected for tests.
@Observable
@MainActor
final class SecurityService {
    typealias Authenticator = @Sendable () async -> Bool

    static let lockEnabledKey = "appLockEnabled"

    private let authenticate: Authenticator
    private let defaults: UserDefaults

    private(set) var isLocked: Bool
    private(set) var isLockEnabled: Bool

    init(authenticate: Authenticator? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.authenticate = authenticate ?? Self.biometricAuthenticator
        let enabled = defaults.bool(forKey: Self.lockEnabledKey)
        self.isLockEnabled = enabled
        // Cold start with lock enabled → start locked.
        self.isLocked = enabled
    }

    /// Toggling the lock in either direction requires proving you can pass it.
    @discardableResult
    func setLockEnabled(_ enabled: Bool) async -> Bool {
        guard await authenticate() else { return false }
        isLockEnabled = enabled
        defaults.set(enabled, forKey: Self.lockEnabledKey)
        if !enabled {
            isLocked = false
        }
        return true
    }

    /// Called when the app enters the background.
    func lockIfEnabled() {
        if isLockEnabled {
            isLocked = true
        }
    }

    @discardableResult
    func attemptUnlock() async -> Bool {
        guard isLocked else { return true }
        guard await authenticate() else { return false }
        isLocked = false
        return true
    }

    private static let biometricAuthenticator: Authenticator = {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode set on the device: never brick the journal.
            return true
        }
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: String(localized: "Unlock your journal")
            )
        } catch {
            return false
        }
    }
}
