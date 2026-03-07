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

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: "warning_threshold")
        super.tearDown()
    }

    func testPasswordCacheSaveLoadMarksFromCache() {
        let info = PasswordInfo(
            lastSetDate: Date(timeIntervalSince1970: 0),
            daysUntilExpiration: 7,
            expiryDate: Date(timeIntervalSince1970: 60),
            isFromCache: false
        )

        PasswordCache.shared.save(info)

        let loaded = PasswordCache.shared.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.daysUntilExpiration, 7)
        XCTAssertEqual(loaded?.expiryDate, Date(timeIntervalSince1970: 60))
        XCTAssertEqual(loaded?.lastSetDate, Date(timeIntervalSince1970: 0))
        XCTAssertTrue(loaded?.isFromCache ?? false)
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
    func testNotificationResetClearsDailyState() {
        let manager = NotificationManager.shared
        manager.markNotificationAsShown()
        XCTAssertTrue(manager.isNotificationShownToday)
        manager.resetDailyNotificationState()
        XCTAssertFalse(manager.isNotificationShownToday)
    }
}
