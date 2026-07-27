// SecurityServiceTests.swift

import Foundation
import Testing
@testable import Ember

@MainActor
@Suite("Security service")
struct SecurityServiceTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "security-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func enablingRequiresSuccessfulAuth() async {
        let defaults = makeDefaults()
        let denied = SecurityService(authenticate: { false }, defaults: defaults)
        #expect(await denied.setLockEnabled(true) == false)
        #expect(!denied.isLockEnabled)

        let granted = SecurityService(authenticate: { true }, defaults: defaults)
        #expect(await granted.setLockEnabled(true) == true)
        #expect(granted.isLockEnabled)
        #expect(defaults.bool(forKey: SecurityService.lockEnabledKey))
    }

    @Test func coldStartWithLockEnabledStartsLocked() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: SecurityService.lockEnabledKey)
        let service = SecurityService(authenticate: { true }, defaults: defaults)
        #expect(service.isLocked)
    }

    @Test func backgroundingLocksOnlyWhenEnabled() async {
        let defaults = makeDefaults()
        let service = SecurityService(authenticate: { true }, defaults: defaults)

        service.lockIfEnabled()
        #expect(!service.isLocked, "lock disabled → backgrounding must not lock")

        await service.setLockEnabled(true)
        service.lockIfEnabled()
        #expect(service.isLocked)
    }

    @Test func failedUnlockStaysLocked() async {
        let defaults = makeDefaults()
        defaults.set(true, forKey: SecurityService.lockEnabledKey)
        let service = SecurityService(authenticate: { false }, defaults: defaults)

        #expect(await service.attemptUnlock() == false)
        #expect(service.isLocked)
    }

    @Test func successfulUnlockUnlocks() async {
        let defaults = makeDefaults()
        defaults.set(true, forKey: SecurityService.lockEnabledKey)
        let service = SecurityService(authenticate: { true }, defaults: defaults)

        #expect(await service.attemptUnlock() == true)
        #expect(!service.isLocked)
    }

    @Test func disablingClearsTheLock() async {
        let defaults = makeDefaults()
        defaults.set(true, forKey: SecurityService.lockEnabledKey)
        let service = SecurityService(authenticate: { true }, defaults: defaults)
        #expect(service.isLocked)

        await service.setLockEnabled(false)
        #expect(!service.isLocked)
        #expect(!service.isLockEnabled)
    }
}
