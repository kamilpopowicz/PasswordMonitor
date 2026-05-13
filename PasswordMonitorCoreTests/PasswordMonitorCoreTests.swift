//
//  PasswordMonitorCoreTests.swift
//  PasswordMonitorCoreTests
//
//  Created by Kamil Popowicz on 19/02/2026.
//

import XCTest
@testable import PasswordMonitorCore

final class PasswordMonitorCoreTests: XCTestCase {
    private let cacheKey = "cached_password_info"
    private let sharedDefaults = UserDefaults(suiteName: "popo.PasswordMonitor")

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        sharedDefaults?.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: "cached_password_info_last_fetch_cache")
        sharedDefaults?.removeObject(forKey: "cached_password_info_last_fetch_cache")
        UserDefaults.standard.removeObject(forKey: "warning_threshold")
        UserDefaults.standard.removeObject(forKey: "notification_hour")
        UserDefaults.standard.removeObject(forKey: "quiet_hours_start")
        UserDefaults.standard.removeObject(forKey: "quiet_hours_end")
        NotificationStateStore.shared.clearNotificationDeliveryClaim()
        NotificationStateStore.shared.clearScheduledNotificationEventClaim()
        NotificationStateStore.shared.clearHelperTriggerClaim()
        super.tearDown()
    }

    func testPasswordCacheSaveLoadMarksFromCache() {
        let expiryDate = Date().addingTimeInterval(10 * 24 * 3600 + 3600)
        let info = PasswordInfo(
            lastSetDate: Date(timeIntervalSince1970: 0),
            daysUntilExpiration: 7,
            expiryDate: expiryDate,
            isFromCache: false
        )

        PasswordCache.shared.save(info)
        PasswordCache.shared.markLastFetchWasCache(true)

        let loaded = PasswordCache.shared.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.daysUntilExpiration, 10)
        XCTAssertEqual(loaded?.expiryDate.timeIntervalSince1970 ?? 0, expiryDate.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(loaded?.lastSetDate, Date(timeIntervalSince1970: 0))
        XCTAssertTrue(loaded?.isFromCache ?? false)
        XCTAssertNotNil(sharedDefaults?.data(forKey: cacheKey))
    }

    func testPasswordExpirationMathUsesSameDayCountAsAlertLogic() {
        let now = Date(timeIntervalSince1970: 0)
        let expirationDate = now.addingTimeInterval(6 * 24 * 3600 + 23 * 3600)

        let daysRemaining = PasswordExpirationMath.daysRemaining(until: expirationDate, from: now)
        XCTAssertEqual(daysRemaining, 6)
    }

    func testPasswordCacheLoadInvalidDataReturnsNil() {
        UserDefaults.standard.set(Data([0x00, 0x01, 0x02]), forKey: cacheKey)
        let loaded = PasswordCache.shared.load()
        XCTAssertNil(loaded)
    }

    func testParseSMBPasswordLastSetEpoch() throws {
        let output = "SMBPasswordLastSet: 116444736000000000\n"
        let date = try ActiveDirectoryManager.parseSMBPasswordLastSet(from: output)
        XCTAssertEqual(date, Date(timeIntervalSince1970: 0))
    }

    func testParseSMBPasswordLastSetInvalid() {
        XCTAssertThrowsError(try ActiveDirectoryManager.parseSMBPasswordLastSet(from: "nope"))
    }

    func testParseSMBPasswordLastSetSelectsLatestWhenMultipleLines() throws {
        let output = """
        SMBPasswordLastSet: 116444736000000000
        SMBPasswordLastSet: 116444736100000000
        """
        let date = try ActiveDirectoryManager.parseSMBPasswordLastSet(from: output)
        XCTAssertEqual(date, Date(timeIntervalSince1970: 10))
    }

    func testSystemADDomainResolverParsesDomainFromOutput() {
        let output = """
        Active Directory Domain = corp.example.com
        Active Directory Forest = CORP.EXAMPLE.COM
        """

        XCTAssertEqual(SystemADDomainResolver.parseDomain(from: output), "corp.example.com")
    }

    func testSystemADDomainResolverReturnsNilForMissingDomain() {
        let output = "Some unrelated configuration"
        XCTAssertNil(SystemADDomainResolver.parseDomain(from: output))
    }

    func testSystemADDomainResolverMatchesShortNodeNameFromFQDN() {
        let nodes = ["EXAMPLE", "OTHER"]
        XCTAssertEqual(
            SystemADDomainResolver.matchingNode(for: "example.local", nodes: nodes),
            "EXAMPLE"
        )
    }

    func testSystemADDomainResolverReturnsNilWhenNodeListDoesNotContainDomain() {
        let nodes = ["EXAMPLE"]
        XCTAssertNil(
            SystemADDomainResolver.matchingNode(for: "unknown.domain", nodes: nodes)
        )
    }

    func testHelperScheduleNextOccurrenceReturnsSameDayFutureTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 3600) // 01:00

        let next = HelperSchedule.nextOccurrence(for: "09:00", after: now, calendar: calendar)
        XCTAssertEqual(next, Date(timeIntervalSince1970: 9 * 3600))
    }

    func testHelperScheduleNextOccurrenceRollsToNextDayWhenTimePassed() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 10 * 3600) // 10:00

        let next = HelperSchedule.nextOccurrence(for: "09:00", after: now, calendar: calendar)
        XCTAssertEqual(next, Date(timeIntervalSince1970: 33 * 3600))
    }

    func testHelperScheduleQuietHoursOvernightRange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let evening = Date(timeIntervalSince1970: (19 * 3600))
        let earlyMorning = Date(timeIntervalSince1970: (5 * 3600))
        let midday = Date(timeIntervalSince1970: (12 * 3600))

        XCTAssertTrue(
            HelperSchedule.isWithinQuietHours(
                date: evening,
                startTime: "18:01",
                endTime: "05:59",
                calendar: calendar
            )
        )
        XCTAssertTrue(
            HelperSchedule.isWithinQuietHours(
                date: earlyMorning,
                startTime: "18:01",
                endTime: "05:59",
                calendar: calendar
            )
        )
        XCTAssertFalse(
            HelperSchedule.isWithinQuietHours(
                date: midday,
                startTime: "18:01",
                endTime: "05:59",
                calendar: calendar
            )
        )
    }

    func testHelperScheduleQuietHoursDisabledWhenStartEqualsEnd() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let sample = Date(timeIntervalSince1970: (22 * 3600))

        XCTAssertFalse(
            HelperSchedule.isWithinQuietHours(
                date: sample,
                startTime: "00:00",
                endTime: "00:00",
                calendar: calendar
            )
        )
    }

    func testHelperScheduleSlotIDUsesConfiguredNotificationTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let sample = Date(timeIntervalSince1970: (30 * 24 * 3600) + (8 * 3600) + (45 * 60))

        XCTAssertEqual(
            HelperSchedule.scheduledSlotID(for: sample, timeString: "10:00", calendar: calendar),
            "1970-01-31@10:00"
        )
    }

    @MainActor
    func testScheduledNotificationEventKeyUsesConfiguredNotificationTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let sample = Date(timeIntervalSince1970: (30 * 24 * 3600) + (8 * 3600) + (45 * 60))
        UserDefaults.standard.set("10:00", forKey: "notification_hour")

        XCTAssertEqual(
            NotificationManager.scheduledNotificationEventKey(
                now: sample,
                defaults: .standard,
                calendar: calendar
            ),
            "1970-01-31@10:00"
        )
    }

    func testHelperScheduleTriggerBucketIDUsesMinutePrecision() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let sample = Date(timeIntervalSince1970: (30 * 24 * 3600) + (8 * 3600) + (45 * 60) + 34)

        XCTAssertEqual(
            HelperSchedule.triggerBucketID(for: sample, calendar: calendar),
            "1970-01-31@08:45"
        )
    }

    @MainActor
    func testResolvedWarningThresholdFallsBackToSevenDays() {
        XCTAssertEqual(NotificationManager.resolvedWarningThreshold(), 7)
    }

    @MainActor
    func testResolvedWarningThresholdUsesSavedValue() {
        UserDefaults.standard.set(14, forKey: "warning_threshold")
        XCTAssertEqual(NotificationManager.resolvedWarningThreshold(), 14)
    }

    @MainActor
    func testIsWithinWarningThresholdReturnsFalseBeforeThreshold() {
        let now = Date(timeIntervalSince1970: 0)
        let expirationDate = now.addingTimeInterval(8 * 24 * 3600)

        XCTAssertFalse(
            NotificationManager.isWithinWarningThreshold(
                now: now,
                expirationDate: expirationDate,
                thresholdDays: 7
            )
        )
    }

    @MainActor
    func testIsWithinWarningThresholdReturnsTrueAtThreshold() {
        let now = Date(timeIntervalSince1970: 0)
        let expirationDate = now.addingTimeInterval(7 * 24 * 3600)

        XCTAssertTrue(
            NotificationManager.isWithinWarningThreshold(
                now: now,
                expirationDate: expirationDate,
                thresholdDays: 7
            )
        )
    }

    @MainActor
    func testAutomaticNotificationsAreSuppressedDuringQuietHours() {
        UserDefaults.standard.set("18:01", forKey: "quiet_hours_start")
        UserDefaults.standard.set("05:59", forKey: "quiet_hours_end")
        let quietTime = Date(timeIntervalSince1970: 20 * 3600)

        XCTAssertTrue(
            NotificationManager.isNotificationSuppressedForQuietHours(
                reason: .automatic,
                now: quietTime
            )
        )
    }

    @MainActor
    func testScheduledNotificationsAreAllowedDuringQuietHours() {
        UserDefaults.standard.set("18:01", forKey: "quiet_hours_start")
        UserDefaults.standard.set("05:59", forKey: "quiet_hours_end")
        let quietTime = Date(timeIntervalSince1970: 20 * 3600)

        XCTAssertFalse(
            NotificationManager.isNotificationSuppressedForQuietHours(
                reason: .scheduledTime,
                now: quietTime
            )
        )
    }

    @MainActor
    func testAutomaticNotificationsRespectActiveSnooze() {
        let now = Date(timeIntervalSince1970: 1000)
        let snoozeEnd = now.addingTimeInterval(3600)

        XCTAssertTrue(
            NotificationManager.isNotificationSuppressedBySnooze(
                reason: .automatic,
                isSnoozed: true,
                snoozeEndTime: snoozeEnd,
                now: now
            )
        )
    }

    @MainActor
    func testManualNotificationsAreAllowedDuringQuietHours() {
        UserDefaults.standard.set("18:01", forKey: "quiet_hours_start")
        UserDefaults.standard.set("05:59", forKey: "quiet_hours_end")
        let quietTime = Date(timeIntervalSince1970: 20 * 3600)

        XCTAssertFalse(
            NotificationManager.isNotificationSuppressedForQuietHours(
                reason: .manual,
                now: quietTime
            )
        )
    }

    @MainActor
    func testManualNotificationsBypassActiveSnooze() {
        let now = Date(timeIntervalSince1970: 1000)
        let snoozeEnd = now.addingTimeInterval(3600)

        XCTAssertFalse(
            NotificationManager.isNotificationSuppressedBySnooze(
                reason: .manual,
                isSnoozed: true,
                snoozeEndTime: snoozeEnd,
                now: now
            )
        )
    }

    @MainActor
    func testScheduledNotificationsBypassActiveSnooze() {
        let now = Date(timeIntervalSince1970: 1000)
        let snoozeEnd = now.addingTimeInterval(3600)

        XCTAssertFalse(
            NotificationManager.isNotificationSuppressedBySnooze(
                reason: .scheduledTime,
                isSnoozed: true,
                snoozeEndTime: snoozeEnd,
                now: now
            )
        )
    }

    @MainActor
    func testNotificationResetClearsDailyState() {
        let manager = NotificationManager.shared
        manager.markNotificationAsShown()
        XCTAssertTrue(manager.isNotificationShownToday)
        manager.resetDailyNotificationState()
        XCTAssertFalse(manager.isNotificationShownToday)
    }

    func testNotificationDeliveryClaimBlocksImmediateDuplicate() {
        let store = NotificationStateStore.shared
        let now = Date(timeIntervalSince1970: 1_000)
        let expiryDate = Date(timeIntervalSince1970: 10_000)

        XCTAssertTrue(store.claimNotificationDelivery(expirationDate: expiryDate, now: now))
        XCTAssertFalse(store.claimNotificationDelivery(expirationDate: expiryDate, now: now))
    }

    func testNotificationDeliveryClaimExpiresAfterWindow() {
        let store = NotificationStateStore.shared
        let now = Date(timeIntervalSince1970: 1_000)
        let expiryDate = Date(timeIntervalSince1970: 10_000)

        XCTAssertTrue(store.claimNotificationDelivery(expirationDate: expiryDate, now: now))
        XCTAssertTrue(store.claimNotificationDelivery(expirationDate: expiryDate, now: now.addingTimeInterval(121)))
    }

    func testNotificationDeliveryClaimAllowsDifferentExpirationDate() {
        let store = NotificationStateStore.shared
        let now = Date(timeIntervalSince1970: 1_000)
        let firstExpiry = Date(timeIntervalSince1970: 10_000)
        let secondExpiry = Date(timeIntervalSince1970: 20_000)

        XCTAssertTrue(store.claimNotificationDelivery(expirationDate: firstExpiry, now: now))
        XCTAssertTrue(store.claimNotificationDelivery(expirationDate: secondExpiry, now: now.addingTimeInterval(1)))
    }

    func testScheduledNotificationEventClaimBlocksDuplicateSlot() {
        let store = NotificationStateStore.shared
        let now = Date(timeIntervalSince1970: 1_000)
        let eventKey = "2026-04-29@10:00"

        XCTAssertTrue(store.claimScheduledNotificationEvent(eventKey: eventKey, now: now))
        XCTAssertFalse(store.claimScheduledNotificationEvent(eventKey: eventKey, now: now.addingTimeInterval(30)))
    }

    func testScheduledNotificationEventClaimAllowsDifferentSlot() {
        let store = NotificationStateStore.shared
        let now = Date(timeIntervalSince1970: 1_000)
        let eventKey = "2026-04-29@10:00"
        let otherEventKey = "2026-04-29@13:00"

        XCTAssertTrue(store.claimScheduledNotificationEvent(eventKey: eventKey, now: now))
        XCTAssertTrue(store.claimScheduledNotificationEvent(eventKey: otherEventKey, now: now.addingTimeInterval(30)))
    }

    func testHelperTriggerClaimBlocksDuplicateRequest() {
        let store = NotificationStateStore.shared
        let now = Date(timeIntervalSince1970: 1_000)
        let triggerKey = "helper:scheduled:2026-04-29@10:00"

        XCTAssertTrue(store.claimHelperTrigger(triggerKey: triggerKey, now: now))
        XCTAssertFalse(store.claimHelperTrigger(triggerKey: triggerKey, now: now.addingTimeInterval(10)))
    }

    func testHelperTriggerClaimAllowsDifferentRequest() {
        let store = NotificationStateStore.shared
        let now = Date(timeIntervalSince1970: 1_000)
        let firstTriggerKey = "helper:scheduled:2026-04-29@10:00"
        let secondTriggerKey = "helper:wake:2026-04-29@10:01"

        XCTAssertTrue(store.claimHelperTrigger(triggerKey: firstTriggerKey, now: now))
        XCTAssertTrue(store.claimHelperTrigger(triggerKey: secondTriggerKey, now: now.addingTimeInterval(30)))
    }

    func testHelperProcessCleanupSelectsOnlyHelpersFromDifferentBundlePath() {
        let expectedPath = "/Applications/PasswordMonitor.app/Contents/Library/LoginItems/PasswordMonitorHelperApp.app"
        let stalePath = "/Users/test/Desktop/PasswordMonitor.app/Contents/Library/LoginItems/PasswordMonitorHelperApp.app"
        let helpers = [
            HelperProcessCleanup.RunningHelper(processIdentifier: 10, bundlePath: expectedPath),
            HelperProcessCleanup.RunningHelper(processIdentifier: 11, bundlePath: stalePath),
            HelperProcessCleanup.RunningHelper(processIdentifier: 12, bundlePath: nil)
        ]

        let staleHelpers = HelperProcessCleanup.staleHelpers(
            expectedBundlePath: expectedPath,
            runningHelpers: helpers
        )

        XCTAssertEqual(staleHelpers.map(\.processIdentifier), [11, 12])
    }

    func testHelperProcessCleanupDoesNotSelectCurrentHelperAsDuplicate() {
        let helpers = [
            HelperProcessCleanup.RunningHelper(processIdentifier: 20, bundlePath: "/current/helper.app"),
            HelperProcessCleanup.RunningHelper(processIdentifier: 21, bundlePath: "/stale/helper.app")
        ]

        let duplicates = HelperProcessCleanup.duplicateHelpers(
            currentProcessIdentifier: 20,
            runningHelpers: helpers
        )

        XCTAssertEqual(duplicates.map(\.processIdentifier), [21])
    }

    func testAppUninstallCleanupPlanIncludesHelperPreferencesAndUserData() {
        let home = URL(fileURLWithPath: "/Users/test")
        let paths = AppUninstallCleanupPlan.userDataPaths(
            homeDirectory: home,
            userInstalledAppURL: home.appendingPathComponent("Applications/PasswordMonitor.app"),
            desktopAppURL: home.appendingPathComponent("Desktop/PasswordMonitor/PasswordMonitor.app")
        ).map(\.path)

        XCTAssertTrue(paths.contains("/Users/test/Library/Preferences/popo.PasswordMonitor.plist"))
        XCTAssertTrue(paths.contains("/Users/test/Library/Preferences/popo.PasswordMonitorHelperApp.plist"))
        XCTAssertTrue(paths.contains("/Users/test/Library/Containers/popo.PasswordMonitorHelperApp"))
        XCTAssertTrue(paths.contains("/Users/test/Library/LaunchAgents/com.company.password-monitor.plist"))
        XCTAssertTrue(paths.contains("/Users/Shared/password-monitor.sh"))
        XCTAssertTrue(paths.contains("/tmp/password-monitor.out"))
        XCTAssertTrue(paths.contains("/tmp/password-monitor.err"))
        XCTAssertTrue(paths.contains("/Applications/PasswordMonitor.app"))
        XCTAssertTrue(paths.contains("/Users/test/Applications/PasswordMonitor.app"))
        XCTAssertTrue(paths.contains("/Users/test/Desktop/PasswordMonitor/PasswordMonitor.app"))
        XCTAssertTrue(AppUninstallCleanupPlan.preferenceDomains.contains("popo.PasswordMonitorHelperApp"))
        XCTAssertTrue(AppUninstallCleanupPlan.loginItemIdentifiers.contains("com.company.password-monitor"))
    }

    @MainActor
    func testDuplicateNotificationPresentationIsSuppressedForSameExpirationDate() {
        let now = Date(timeIntervalSince1970: 1_000)
        let expirationDate = Date(timeIntervalSince1970: 10_000)
        let lastPresentedAt = now.addingTimeInterval(-30)

        XCTAssertTrue(
            NotificationManager.shouldSuppressDuplicateNotificationPresentation(
                reason: .scheduledTime,
                expirationDate: expirationDate,
                lastPresentedExpirationDate: expirationDate,
                lastPresentedAt: lastPresentedAt,
                now: now,
                duplicatePresentationWindow: 120
            )
        )
    }

    @MainActor
    func testDuplicateNotificationPresentationAllowsDifferentExpirationDate() {
        let now = Date(timeIntervalSince1970: 1_000)
        let expirationDate = Date(timeIntervalSince1970: 10_000)
        let otherExpirationDate = Date(timeIntervalSince1970: 11_000)
        let lastPresentedAt = now.addingTimeInterval(-30)

        XCTAssertFalse(
            NotificationManager.shouldSuppressDuplicateNotificationPresentation(
                reason: .checkNow,
                expirationDate: expirationDate,
                lastPresentedExpirationDate: otherExpirationDate,
                lastPresentedAt: lastPresentedAt,
                now: now,
                duplicatePresentationWindow: 120
            )
        )
    }

    @MainActor
    func testDuplicateNotificationPresentationDoesNotSuppressManualCheckNow() {
        let now = Date(timeIntervalSince1970: 1_000)
        let expirationDate = Date(timeIntervalSince1970: 10_000)
        let lastPresentedAt = now.addingTimeInterval(-30)

        XCTAssertFalse(
            NotificationManager.shouldSuppressDuplicateNotificationPresentation(
                reason: .checkNow,
                expirationDate: expirationDate,
                lastPresentedExpirationDate: expirationDate,
                lastPresentedAt: lastPresentedAt,
                now: now,
                duplicatePresentationWindow: 120
            )
        )
    }
}
